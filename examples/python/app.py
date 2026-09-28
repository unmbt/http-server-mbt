"""Run: uvicorn app:app --app-dir examples/python --lifespan on"""
import os
from fastapi import FastAPI
from hs_asgi import StaticMiddleware

api = FastAPI()


@api.get("/api/health")
async def health():
    return {"source": "FastAPI", "ok": True}


app = StaticMiddleware(api, library=os.environ["HS_LIBRARY"],
                       config={"root": os.environ.get("HS_ROOT", ".")})

if __name__ == "__main__":
    import uvicorn

    class DemoServer(uvicorn.Server):
        async def startup(self, sockets=None):
            await super().startup(sockets)
            if self.started:
                print("LISTENING", self.servers[0].sockets[0].getsockname()[1], flush=True)

    server = DemoServer(uvicorn.Config(app, host="127.0.0.1", port=0, lifespan="on", log_level="error"))

    @api.get("/__shutdown")
    async def shutdown():
        server.should_exit = True
        return {"stopping": True}

    server.run()
