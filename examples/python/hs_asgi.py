"""ASGI middleware: host owns HTTP/TLS; ABI engine owns static file I/O."""
import asyncio
from hs_async import Engine


class StaticMiddleware:
    def __init__(self, app, *, library, config):
        self.app, self.library = app, library
        self.config = {"handle_error": False, "cache_control": "no-cache", **config}
        self.engine = None

    async def __call__(self, scope, receive, send):
        if scope["type"] == "lifespan":
            async def lifecycle_receive():
                message = await receive()
                if message["type"] == "lifespan.startup":
                    self.engine = await Engine.create(self.library, self.config)
                elif message["type"] == "lifespan.shutdown" and self.engine:
                    await self.engine.aclose()
                return message
            try:
                await self.app(scope, lifecycle_receive, send)
            finally:
                if self.engine:
                    await self.engine.aclose()
            return
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        if self.engine is None:
            raise RuntimeError("StaticMiddleware requires ASGI lifespan startup")
        target = scope.get("raw_path", scope["path"].encode("utf-8"))
        if scope.get("query_string"):
            target += b"?" + scope["query_string"]
        response = await self.engine.handle_request(scope["method"], target, scope.get("headers", ()))
        if response is None:
            await self.app(scope, receive, send)
            return

        async def stream():
            await send({"type": "http.response.start", "status": response.status,
                        "headers": [(k.lower().encode("utf-8"), v.encode("utf-8")) for k, v in response.headers]})
            async for chunk in response:
                await send({"type": "http.response.body", "body": chunk, "more_body": True})
            await send({"type": "http.response.body", "body": b"", "more_body": False})

        async def disconnected():
            while True:
                if (await receive())["type"] == "http.disconnect":
                    return

        producer = asyncio.create_task(stream())
        watcher = asyncio.create_task(disconnected())
        try:
            done, _ = await asyncio.wait([producer, watcher], return_when=asyncio.FIRST_COMPLETED)
            if producer in done:
                await producer  # Propagate FILE_CHANGED/I/O errors; never synthesize EOF.
        finally:
            producer.cancel()
            watcher.cancel()
            try:
                await asyncio.gather(producer, watcher, return_exceptions=True)
            finally:
                await response.aclose()
