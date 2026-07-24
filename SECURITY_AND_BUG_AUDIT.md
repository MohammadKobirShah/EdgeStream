# EdgeStream deep audit

## Fixed in the current repository

- HTML-escaped and malformed Python/shell syntax was normalized.
- Cache no longer depends on a Railway Volume.
- Cache defaults to `500m` and media/fallback objects use a 60-second freshness window.
- Cache cleanup uses both `inactive=60s` and `max_size=500m`.
- Router disables upstream compression before `sub_filter`, so playlist rewriting can work.
- Python shutdown awaits the cancelled health task.
- Nginx startup is checked with `nginx -t`.
- Cache and router configs are generated from environment variables at startup.
- Health checks run concurrently.

## Important remaining production considerations

### 1. Ephemeral storage is not a guaranteed 1 TB disk

`CACHE_MAX_SIZE=500m` is only an Nginx cache ceiling. The actual container filesystem capacity is controlled by Railway and the service plan. Do not set a value larger than the available ephemeral disk. All cache content disappears after restart/redeploy.

### 2. One minute is approximate, not an exact retention guarantee

`proxy_cache_valid 200 60s` controls freshness and `inactive=60s` controls idle-file cleanup. Nginx's cache manager runs asynchronously, and actively requested objects can remain longer. `max_size` is the hard operational guardrail.

### 3. Readiness is optimistic during the first health-check interval

Nodes are initially marked healthy so Nginx can serve immediately. `/ready` can therefore report ready before the first health-check round proves connectivity. For strict readiness, add a startup probe state and return 503 until the first round completes.

### 4. Health checks only test the cache process

`/health` returns 200 without checking origin connectivity, cache writability, or free space. This is intentional to avoid making origin availability a router-node liveness condition, but a separate playback/origin monitoring check is recommended.

### 5. Playlist rewriting is literal host substitution

Only absolute URLs containing the exact origin hostname are rewritten. Relative URLs, origin ports, alternate hostnames, protocol-relative URLs, and URLs with different casing are not rewritten. Validate this against a real origin playlist.

### 6. TLS verification is disabled to the origin

The cache uses `proxy_ssl_verify off`. This avoids CA problems but permits a man-in-the-middle between cache and origin. For a controlled origin, enable certificate verification and install/configure the correct CA chain.

### 7. Public control-plane endpoints need protection

`/metrics` and `/metrics/nodes` are reachable through the public router hostname. Put them behind Cloudflare Access, an allowlist, or a private hostname if node topology and metrics should not be public.

### 8. Cache content must be public

Do not use this cache for personalized or authorization-protected media unless cache keys and response-header rules are redesigned. Query strings are included in `$request_uri`, but the cache should still not receive secrets or user-specific content.

### 9. Two cache nodes are independent

There is no shared cache. A request routed to a different node can miss even when another node has the object. This is expected. Use sticky routing or accept duplicated origin fetches if a single-node hit ratio is required.

### 10. Dynamic reload writes should be atomic

The registry currently writes the upstream file and then reloads Nginx. For maximum resilience, write a temporary file in the same directory and use `os.replace()` before reload, so Nginx never observes a partially written include.

### 11. Environment values need validation

`CACHE_NODES`, `EDGE_DOMAIN`, and origin URL parts are trusted deployment variables. Add hostname/URL validation before interpolating them into Nginx if these values can be changed by untrusted automation.

### 12. Pin the Cloudflared image

`cloudflare/cloudflared:latest` can change behavior unexpectedly. Pin a tested version after the first successful deployment.
