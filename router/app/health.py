import asyncio
import httpx
import structlog
from .config import HEALTH_CHECK_INTERVAL, HEALTH_CHECK_TIMEOUT, HEALTH_FAIL_THRESHOLD, HEALTH_RECOVERY_THRESHOLD
from .registry import node_registry

logger = structlog.get_logger()

async def check_node(client: httpx.AsyncClient, host: str) -> tuple[str, bool]:
    try:
        response = await client.get(f"http://{host}:8080/health", timeout=HEALTH_CHECK_TIMEOUT)
        return host, response.status_code == 200
    except Exception:
        return host, False

async def health_loop() -> None:
    await asyncio.sleep(2)
    timeout = httpx.Timeout(HEALTH_CHECK_TIMEOUT)
    async with httpx.AsyncClient(timeout=timeout) as client:
        while True:
            hosts = node_registry.all_hosts()
            if hosts:
                results = await asyncio.gather(*(check_node(client, host) for host in hosts))
                rebuild_needed = False
                for host, ok in results:
                    node = node_registry.nodes[host]
                    if ok:
                        node.consecutive_success += 1
                        node.consecutive_fail = 0
                        if not node.healthy and node.consecutive_success >= HEALTH_RECOVERY_THRESHOLD:
                            node.healthy = True
                            logger.info("node_recovered", host=host)
                            rebuild_needed = True
                    else:
                        node.consecutive_fail += 1
                        node.consecutive_success = 0
                        if node.healthy and node.consecutive_fail >= HEALTH_FAIL_THRESHOLD:
                            node.healthy = False
                            logger.warning("node_failed", host=host)
                            rebuild_needed = True
                if rebuild_needed:
                    await node_registry.rebuild_upstream()
                node_registry.health_checked = True
            await asyncio.sleep(HEALTH_CHECK_INTERVAL)
