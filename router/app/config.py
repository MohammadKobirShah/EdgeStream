import os

ORIGIN_M3U8_URL = os.getenv("ORIGIN_M3U8_URL", "")
EDGE_DOMAIN = os.getenv("EDGE_DOMAIN", "")
CACHE_NODES = [n.strip() for n in os.getenv("CACHE_NODES", "").split(",") if n.strip()]
LB_STRATEGY = os.getenv("LB_STRATEGY", "least_conn")
HEALTH_CHECK_INTERVAL = int(os.getenv("HEALTH_CHECK_INTERVAL", "10"))
HEALTH_CHECK_TIMEOUT = float(os.getenv("HEALTH_CHECK_TIMEOUT", "3"))
HEALTH_FAIL_THRESHOLD = int(os.getenv("HEALTH_FAIL_THRESHOLD", "2"))
HEALTH_RECOVERY_THRESHOLD = int(os.getenv("HEALTH_RECOVERY_THRESHOLD", "2"))
UPSTREAM_CONF_PATH = os.getenv("UPSTREAM_CONF_PATH", "/etc/nginx/conf.d/upstream.conf")
