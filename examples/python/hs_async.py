"""ctypes/asyncio adapter for ABI 1.1. Explicit close; no runtime polling."""
import asyncio
import ctypes as C
import json
from pathlib import Path


class Span(C.Structure):
    _fields_ = [("data", C.c_void_p), ("length", C.c_uint64)]


class Header(C.Structure):
    _fields_ = [("name", Span), ("value", Span)]


class Request(C.Structure):
    _fields_ = [("struct_size", C.c_uint32), ("abi_major", C.c_uint32),
                ("method", Span), ("target", Span), ("headers", C.POINTER(Header)),
                ("header_count", C.c_uint32), ("reserved", C.c_uint32)]


class Meta(C.Structure):
    _fields_ = [("struct_size", C.c_uint32), ("abi_major", C.c_uint32),
                ("status", C.c_int32), ("header_count", C.c_uint32),
                ("headers", C.POINTER(Header)), ("content_length", C.c_uint64),
                ("has_content_length", C.c_uint32), ("reserved", C.c_uint32)]


class Event(C.Structure):
    _fields_ = [("struct_size", C.c_uint32), ("abi_major", C.c_uint32),
                ("code", C.c_int32), ("kind", C.c_uint32),
                ("engine", C.c_void_p), ("server", C.c_void_p),
                ("response", C.c_void_p), ("chunk", C.c_void_p)]


Callback = C.CFUNCTYPE(None, C.c_void_p, C.POINTER(Event))
CODES = ["OK", "CONFIG", "INVALID_ARGUMENT", "IO", "CLOSED", "UNSUPPORTED",
         "UPSTREAM", "TIMEOUT", "CANCELLED", "FILE_CHANGED", "LIMIT", "BUSY", "ABI_MISMATCH"]


class NativeError(Exception):
    def __init__(self, code):
        self.code = CODES[code] if 0 <= code < len(CODES) else "IO"
        super().__init__(self.code)


def text(span):
    return C.string_at(span.data, span.length).decode("utf-8")


class Engine:
    def __init__(self, library):
        self.lib = C.CDLL(str(Path(library).resolve()))
        self.loop = asyncio.get_running_loop()
        self.pending = {}
        self.serial = 0
        self.handle = None
        self.close_task = None
        self.responses = set()
        self.callback = Callback(self._notified)
        p, i = C.c_void_p, C.c_int32
        signatures = {
            "hs_abi_version": ([], C.c_uint32),
            "hs_engine_create_async": ([C.c_char_p, C.c_size_t, Callback, p, C.POINTER(p)], i),
            "hs_engine_close_async": ([p, Callback, p, C.POINTER(p)], i),
            "hs_submit_async": ([p, C.POINTER(Request), Callback, p, C.POINTER(p)], i),
            "hs_response_read_async": ([p, C.c_uint32, Callback, p, C.POINTER(p)], i),
            "hs_response_meta": ([p, C.POINTER(Meta)], i),
            "hs_chunk_data": ([p], Span),
        }
        for name, (args, result) in signatures.items():
            function = getattr(self.lib, name)
            function.argtypes, function.restype = args, result
        for name in ["hs_engine_release", "hs_response_release", "hs_chunk_release",
                     "hs_operation_release", "hs_operation_cancel"]:
            function = getattr(self.lib, name)
            function.argtypes, function.restype = [p], None
        version = self.lib.hs_abi_version()
        if version >> 16 != 1 or version < 0x10001:
            raise NativeError(12)

    @classmethod
    async def create(cls, library, config=None):
        engine = cls(library)
        data = json.dumps(config or {}, ensure_ascii=False).encode("utf-8")
        event = await engine._call(engine.lib.hs_engine_create_async, data, len(data))
        engine.handle = event.engine
        return engine

    def _notified(self, token, event):
        # Copy the borrowed event before returning to C. Handle references are
        # owned by the event recipient and remain alive while queued to asyncio.
        value = Event.from_buffer_copy(event.contents)
        try:
            self.loop.call_soon_threadsafe(self._complete, token, value)
        except RuntimeError:
            # Closing the loop before aclose violates the adapter contract.
            # Still never propagate a Python exception through a C callback.
            if value.response:
                self.lib.hs_response_release(value.response)
            if value.chunk:
                self.lib.hs_chunk_release(value.chunk)
            entry = self.pending.pop(token, None)
            if entry:
                self.lib.hs_operation_release(entry[1])

    def _complete(self, token, event):
        future, operation = self.pending.pop(token)
        self.lib.hs_operation_release(operation)
        if event.code:
            future.set_exception(NativeError(event.code))
        else:
            future.set_result(event)

    async def _call(self, function, *args):
        self.serial += 1
        token = self.serial
        future = self.loop.create_future()
        operation = C.c_void_p()
        self.pending[token] = (future, operation)
        code = function(*args, self.callback, token, C.byref(operation))
        if code:
            del self.pending[token]
            raise NativeError(code)
        try:
            return await asyncio.shield(future)
        except asyncio.CancelledError:
            if not future.done():
                self.lib.hs_operation_cancel(operation)
            async def drain():
                try:
                    event = await future
                except NativeError:
                    return
                if event.response:
                    self.lib.hs_response_release(event.response)
                if event.chunk:
                    self.lib.hs_chunk_release(event.chunk)
                if event.engine:
                    try:
                        await self._call(self.lib.hs_engine_close_async, event.engine)
                    finally:
                        self.lib.hs_engine_release(event.engine)
            cleanup = asyncio.create_task(drain())
            while not cleanup.done():
                try:
                    await asyncio.shield(cleanup)
                except asyncio.CancelledError:
                    pass
            cleanup.result()
            raise

    async def handle_request(self, method, target, headers=()):
        if self.close_task or not self.handle:
            raise NativeError(4)
        buffers = []
        def span(value):
            value = value.encode("utf-8") if isinstance(value, str) else value
            buffer = C.create_string_buffer(value)
            buffers.append(buffer)
            return Span(C.cast(buffer, C.c_void_p), len(value))
        pairs = (Header * len(headers))(*(Header(span(k), span(v)) for k, v in headers))
        request = Request(C.sizeof(Request), 1, span(method), span(target), pairs, len(headers), 0)
        event = await self._call(self.lib.hs_submit_async, self.handle, C.byref(request))
        if event.kind == 4:
            return None
        if self.close_task:
            self.lib.hs_response_release(event.response)
            raise NativeError(4)
        response = Response(self, event.response)
        self.responses.add(response)
        return response

    async def aclose(self):
        if not self.close_task:
            self.close_task = asyncio.create_task(self._close())
        await asyncio.shield(self.close_task)

    async def _close(self):
        if not self.handle:
            return
        for response in list(self.responses):
            await response.aclose()
        await self._call(self.lib.hs_engine_close_async, self.handle)
        # Earlier callbacks have returned; asyncio deliveries can still be queued.
        await asyncio.gather(*(asyncio.shield(f) for f, _ in self.pending.values()), return_exceptions=True)
        self.lib.hs_engine_release(self.handle)
        self.handle = None

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        await self.aclose()


class Response:
    def __init__(self, engine, handle):
        self.engine, self.handle = engine, handle
        meta = Meta(C.sizeof(Meta), 1)
        code = engine.lib.hs_response_meta(handle, C.byref(meta))
        if code:
            engine.lib.hs_response_release(handle)
            raise NativeError(code)
        self.status = meta.status
        self.headers = [(text(meta.headers[i].name), text(meta.headers[i].value)) for i in range(meta.header_count)]
        self.content_length = meta.content_length if meta.has_content_length else None

    def __aiter__(self):
        return self

    async def __anext__(self):
        if not self.handle:
            raise StopAsyncIteration
        try:
            event = await self.engine._call(self.engine.lib.hs_response_read_async, self.handle, 0)
        except BaseException:
            await self.aclose()
            raise
        if event.kind == 6:
            await self.aclose()
            raise StopAsyncIteration
        span = self.engine.lib.hs_chunk_data(event.chunk)
        try:
            return C.string_at(span.data, span.length)
        finally:
            self.engine.lib.hs_chunk_release(event.chunk)

    async def aclose(self):
        if self.handle:
            self.engine.lib.hs_response_release(self.handle)
            self.handle = None
            self.engine.responses.discard(self)

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        await self.aclose()
