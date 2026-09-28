"""Public asyncio consumer; invoked by the MoonBit acceptance driver."""
import asyncio
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "examples" / "python"))
from hs_async import Engine, NativeError


async def main():
    with tempfile.TemporaryDirectory(prefix="hs-python-中文-") as root:
        Path(root, "hello.txt").write_bytes(b"hello async\n")
        Path(root, "large.txt").write_bytes(b"a" * 262144)
        engine = await Engine.create(sys.argv[1], {"root": root, "handle_error": False})
        async with engine:
            response = await engine.handle_request("GET", "/hello.txt")
            assert response.status == 200
            assert b"".join([chunk async for chunk in response]) == b"hello async\n"
            response = await engine.handle_request("HEAD", "/hello.txt")
            assert b"".join([chunk async for chunk in response]) == b""
            response = await engine.handle_request("GET", "/hello.txt", [("Range", "bytes=2-5")])
            assert response.status == 206
            assert b"".join([chunk async for chunk in response]) == b"llo "
            assert await engine.handle_request("GET", "/not-found") is None
            response = await engine.handle_request("GET", "/hello.txt")
            await response.aclose()
            response = await engine.handle_request("GET", "/large.txt")
            assert len(await anext(response)) == 65536
            Path(root, "large.txt").write_bytes(b"changed")
            try:
                await anext(response)
                raise AssertionError("file mutation became EOF")
            except NativeError as error:
                assert error.code == "FILE_CHANGED"
            tasks = [asyncio.create_task(engine.handle_request("GET", "/hello.txt")) for _ in range(32)]
            await asyncio.sleep(0)
            for task in tasks:
                task.cancel()
            for value in await asyncio.gather(*tasks, return_exceptions=True):
                if not isinstance(value, BaseException) and value is not None:
                    await value.aclose()
            response = await engine.handle_request("GET", "/hello.txt")
            async with response:
                async for chunk in response:
                    assert chunk
                    break
            assert response.handle is None
        await engine.aclose()
        try:
            await engine.handle_request("GET", "/hello.txt")
            raise AssertionError("closed engine accepted request")
        except NativeError as error:
            assert error.code == "CLOSED"
        restarted = await Engine.create(sys.argv[1], {"root": root})
        await restarted.aclose()
    print("Python async consumer: GET/HEAD/Range/Next/Unicode/cancel/FILE_CHANGED/close/restart PASS")


asyncio.run(main())
