#!/bin/bash
set -Eeuo pipefail
trap 'echo "ERROR: router startup failed at line $LINENO: $BASH_COMMAND" >&2' ERR

: "${ORIGIN_M3U8_URL:?ORIGIN_M3U8_URL environment variable is not set}"
: "${EDGE_DOMAIN:?EDGE_DOMAIN environment variable is not set}"
if printf "%s" "$EDGE_DOMAIN" | grep -qE '[/:[:space:]]'; then
  echo "ERROR: EDGE_DOMAIN must be a hostname without scheme, port, or path" >&2
  exit 1
fi

export ORIGIN_DOMAIN
ORIGIN_DOMAIN="$(printf '%s' "$ORIGIN_M3U8_URL" | sed -E 's|^https?://([^/:]+).*|\1|')"
if [ -z "$ORIGIN_DOMAIN" ] || [ "$ORIGIN_DOMAIN" = "$ORIGIN_M3U8_URL" ]; then
  echo "ERROR: ORIGIN_M3U8_URL must be an http(s) URL" >&2
  exit 1
fi

echo "Router startup: origin_domain=${ORIGIN_DOMAIN}, edge_domain=${EDGE_DOMAIN}, cache_nodes=${CACHE_NODES:-<none>}"
python3 -c 'from app.registry import generate_initial_upstream; generate_initial_upstream()'
envsubst '${ORIGIN_DOMAIN} ${EDGE_DOMAIN}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -t
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
