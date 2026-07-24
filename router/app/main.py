import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator
from .health import health_loop
from .registry import node_registry
from .config import EDGE_DOMAIN

@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(health_loop())
    try:
        yield
    finally:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)

app = FastAPI(lifespan=lifespan)
Instrumentator().instrument(app).expose(app)

@app.get("/health")
async def health():
    return {"status": "ok", "edge_domain": EDGE_DOMAIN}

@app.get("/ready")
async def ready():
    healthy = node_registry.healthy_hosts()
    return {"ready": node_registry.health_checked and bool(healthy), "healthy_nodes": healthy, "total_nodes": len(node_registry.nodes)}

@app.get("/metrics/nodes")
async def node_metrics():
    return {"total": len(node_registry.nodes), "healthy": len(node_registry.healthy_hosts()), "nodes": {
        host: {"healthy": node.healthy, "consecutive_fail": node.consecutive_fail, "consecutive_success": node.consecutive_success}
        for host, node in node_registry.nodes.items()
    }}
