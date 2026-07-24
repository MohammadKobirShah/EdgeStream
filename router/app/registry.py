import asyncio
import subprocess
import os
from dataclasses import dataclass
from pathlib import Path
import structlog
from .config import CACHE_NODES, LB_STRATEGY, UPSTREAM_CONF_PATH

logger = structlog.get_logger()
STRATEGY_MAP = {"least_conn": "least_conn;", "round_robin": "", "ip_hash": "ip_hash;", "random": "random;"}

@dataclass
class CacheNode:
    host: str
    healthy: bool = True
    consecutive_fail: int = 0
    consecutive_success: int = 0

def build_upstream_conf(hosts: list[str]) -> str:
    strategy = STRATEGY_MAP.get(LB_STRATEGY, "least_conn;")
    lines = ["upstream cache_pool {"]
    if strategy:
        lines.append(f"    {strategy}")
    lines.append("    keepalive 128;")
    if not hosts:
        lines.append("    server 127.0.0.1:8080 down;")
    else:
        for host in hosts:
            lines.append(f"    server {host}:8080 max_fails=3 fail_timeout=10s;")
    lines.append("}")
    return "\n".join(lines) + "\n"

def generate_initial_upstream() -> None:
    path = Path(UPSTREAM_CONF_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(build_upstream_conf(CACHE_NODES), encoding="utf-8")
    os.replace(tmp, path)
    logger.info("initial_upstream_generated", nodes=CACHE_NODES)

class NodeRegistry:
    def __init__(self):
        self.nodes = {host: CacheNode(host=host) for host in CACHE_NODES}
        self._lock = asyncio.Lock()
        self.health_checked = False

    def all_hosts(self) -> list[str]:
        return list(self.nodes)

    def healthy_hosts(self) -> list[str]:
        return [host for host, node in self.nodes.items() if node.healthy]

    async def rebuild_upstream(self) -> None:
        async with self._lock:
            healthy = self.healthy_hosts()
            path = Path(UPSTREAM_CONF_PATH)
            tmp = path.with_name(path.name + ".tmp")
            tmp.write_text(build_upstream_conf(healthy), encoding="utf-8")
            os.replace(tmp, path)
            try:
                proc = await asyncio.create_subprocess_exec(
                    "nginx", "-s", "reload", stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
                )
                _, stderr = await proc.communicate()
                if proc.returncode:
                    logger.error("nginx_reload_failed", stderr=stderr.decode(errors="replace"))
                else:
                    logger.info("upstream_rebuilt", healthy_nodes=healthy)
            except Exception as exc:
                logger.error("nginx_reload_exception", error=str(exc))

node_registry = NodeRegistry()
