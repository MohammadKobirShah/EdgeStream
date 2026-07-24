#!/bin/bash
set -Eeuo pipefail
trap 'echo "ERROR: cache startup failed at line $LINENO: $BASH_COMMAND" >&2' ERR
: "${ORIGIN_M3U8_URL:?ORIGIN_M3U8_URL environment variable is not set}"
ORIGIN_SCHEME_HOST="$(printf '%s' "$ORIGIN_M3U8_URL" | sed -E 's|^(https?://[^/]+).*|\1|')"
case "$ORIGIN_M3U8_URL" in
  http://*|https://*) ;;
  *) echo "ERROR: ORIGIN_M3U8_URL must be an http(s) URL" >&2; exit 1;;
esac
ORIGIN_DOMAIN="$(printf '%s' "$ORIGIN_M3U8_URL" | sed -E 's|^https?://([^/:]+).*|\1|')"
if ! printf '%s' "$ORIGIN_SCHEME_HOST" | grep -qE '^https?://[A-Za-z0-9.-]+(:[0-9]+)?$'; then
  echo "ERROR: ORIGIN_M3U8_URL has an invalid scheme/host" >&2
  exit 1
fi
if ! printf '%s' "$ORIGIN_DOMAIN" | grep -qE '^[A-Za-z0-9.-]+$'; then
  echo "ERROR: origin hostname contains unsupported characters" >&2
  exit 1
fi
CACHE_MAX_SIZE="${CACHE_MAX_SIZE:-500m}"
if ! printf '%s' "$CACHE_MAX_SIZE" | grep -qE '^[0-9]+[kKmMgGtT]$'; then
  echo "ERROR: CACHE_MAX_SIZE must look like 500m, 2g, or 1t" >&2
  exit 1
fi
ORIGIN_TLS_VERIFY="${ORIGIN_TLS_VERIFY:-on}"
case "$ORIGIN_TLS_VERIFY" in
  on|off) ;;
  *) echo "ERROR: ORIGIN_TLS_VERIFY must be on or off" >&2; exit 1;;
esac
export ORIGIN_SCHEME_HOST ORIGIN_DOMAIN CACHE_MAX_SIZE ORIGIN_TLS_VERIFY
mkdir -p /etc/nginx/conf.d /var/cache/hls
chown -R www-data:www-data /var/cache/hls || true
envsubst '${ORIGIN_SCHEME_HOST} ${ORIGIN_DOMAIN} ${CACHE_MAX_SIZE}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
cat > /etc/nginx/conf.d/cache-proxy.inc <<EOF2
proxy_pass ${ORIGIN_SCHEME_HOST}\$request_uri;
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host ${ORIGIN_DOMAIN};
proxy_ssl_server_name on;
proxy_ssl_verify ${ORIGIN_TLS_VERIFY};
proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
proxy_ssl_verify_depth 3;
proxy_cache hls_cache;
proxy_cache_key \$request_uri;
proxy_cache_bypass \$skip_private_auth \$skip_private_cookie;
proxy_no_cache \$skip_private_auth \$skip_private_cookie \$upstream_http_set_cookie;
proxy_cache_valid 404 5s;
proxy_cache_lock on;
proxy_cache_lock_timeout 5s;
proxy_cache_background_update on;
proxy_cache_use_stale updating error timeout http_500 http_502 http_503 http_504;
add_header X-Cache-Status \$upstream_cache_status always;
EOF2
nginx -t
exec nginx -g 'daemon off;'
