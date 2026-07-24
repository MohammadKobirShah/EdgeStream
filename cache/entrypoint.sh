#!/bin/bash
set -eu
: "${ORIGIN_M3U8_URL:?ORIGIN_M3U8_URL environment variable is not set}"
ORIGIN_SCHEME_HOST="$(printf '%s' "$ORIGIN_M3U8_URL" | sed -E 's|^(https?://[^/]+).*|\1|')"
case "$ORIGIN_M3U8_URL" in
  http://*|https://*) ;;
  *) echo "ERROR: ORIGIN_M3U8_URL must be an http(s) URL" >&2; exit 1;;
esac
ORIGIN_DOMAIN="$(printf '%s' "$ORIGIN_M3U8_URL" | sed -E 's|^https?://([^/:]+).*|\1|')"
export ORIGIN_SCHEME_HOST ORIGIN_DOMAIN CACHE_MAX_SIZE="${CACHE_MAX_SIZE:-500m}"
mkdir -p /etc/nginx/conf.d /var/cache/hls
chown -R www-data:www-data /var/cache/hls || true
envsubst '${ORIGIN_SCHEME_HOST} ${ORIGIN_DOMAIN} ${CACHE_MAX_SIZE}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
cat > /etc/nginx/conf.d/cache-proxy.inc <<EOF2
proxy_pass ${ORIGIN_SCHEME_HOST}\$request_uri;
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host ${ORIGIN_DOMAIN};
proxy_ssl_server_name on;
proxy_ssl_verify off;
proxy_cache hls_cache;
proxy_cache_key \$request_uri;
proxy_cache_valid 404 5s;
proxy_cache_lock on;
proxy_cache_lock_timeout 5s;
proxy_cache_background_update on;
proxy_cache_use_stale updating error timeout http_500 http_502 http_503 http_504;
add_header X-Cache-Status \$upstream_cache_status always;
EOF2
nginx -t
exec nginx -g 'daemon off;'
