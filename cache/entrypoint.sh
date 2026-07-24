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
case "$CACHE_MAX_SIZE" in
  unlimited)
    # No max_size directive: Nginx will use available filesystem space.
    CACHE_MAX_DIRECTIVE=""
    ;;
  *[!0-9kKmMgGtT]*|"")
    echo "ERROR: CACHE_MAX_SIZE must look like 500m, 2g, 1t, or unlimited" >&2
    exit 1
    ;;
  *)
    CACHE_MAX_DIRECTIVE="max_size=${CACHE_MAX_SIZE}"
    ;;
esac
ORIGIN_TLS_VERIFY="${ORIGIN_TLS_VERIFY:-on}"
case "$ORIGIN_TLS_VERIFY" in
  on|off) ;;
  *) echo "ERROR: ORIGIN_TLS_VERIFY must be on or off" >&2; exit 1;;
esac
export ORIGIN_SCHEME_HOST ORIGIN_DOMAIN CACHE_MAX_SIZE CACHE_MAX_DIRECTIVE ORIGIN_TLS_VERIFY
mkdir -p /etc/nginx/conf.d /var/cache/hls
chown -R www-data:www-data /var/cache/hls || true
envsubst '${ORIGIN_SCHEME_HOST} ${ORIGIN_DOMAIN} ${CACHE_MAX_SIZE} ${CACHE_MAX_DIRECTIVE}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
cat > /etc/nginx/conf.d/cache-common.inc <<EOF2
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
cat > /etc/nginx/conf.d/cache-origin.inc <<EOF2
# Fixed host without a URI variable: Nginx preserves the incoming request URI.
proxy_pass ${ORIGIN_SCHEME_HOST};
include /etc/nginx/conf.d/cache-common.inc;
EOF2
cat > /etc/nginx/conf.d/manifest-origin.inc <<EOF2
# The root edge URL serves the exact ORIGIN_M3U8_URL manifest.
proxy_pass ${ORIGIN_M3U8_URL};
include /etc/nginx/conf.d/cache-common.inc;
EOF2
nginx -t
exec nginx -g 'daemon off;'
