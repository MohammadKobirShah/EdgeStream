# EdgeStream

A two-tier HLS edge proxy for Railway:

- **Router**: Nginx ingress, rate limiting, cache-node load balancing, health-aware upstream rotation, and playlist URL rewriting.
- **Cache nodes**: Nginx disk cache using the container ephemeral filesystem and connected to the origin.
- **Cloudflared**: Cloudflare Tunnel connector for the public hostname.

> This repository contains deployment-ready configuration, but you must supply your own origin, domain, Railway services, and Cloudflare tunnel token.

## Repository layout

```text
edgestream/
├── router/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── nginx.conf.template
│   ├── railway.toml
│   ├── supervisord.conf
│   └── app/
├── cache/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── nginx.conf.template
│   └── railway.toml
├── cloudflared/
│   ├── Dockerfile
│   └── railway.toml
├── .env.example
└── README.md
```

## Required environment variables

### Router

| Variable | Required | Example | Notes |
|---|---:|---|---|
| `ORIGIN_M3U8_URL` | Yes | `https://origin.example.com/live/index.m3u8` | Used for playlist URL rewriting and validation. |
| `EDGE_DOMAIN` | Yes | `tv.example.com` | Public hostname, without a scheme. |
| `CACHE_NODES` | Recommended | `cache-a.internal,cache-b.internal` | Comma-separated Railway private DNS names. |
| `LB_STRATEGY` | No | `least_conn` | `least_conn`, `round_robin`, `ip_hash`, or `random`. |
| `HEALTH_CHECK_INTERVAL` | No | `10` | Seconds between health-check rounds. |
| `HEALTH_CHECK_TIMEOUT` | No | `3` | Per-node request timeout in seconds. |
| `HEALTH_FAIL_THRESHOLD` | No | `2` | Failures before removing a node. |
| `HEALTH_RECOVERY_THRESHOLD` | No | `2` | Successes before restoring a node. |

### Cache nodes

| Variable | Required | Example |
|---|---:|---|
| `ORIGIN_M3U8_URL` | Yes | `https://origin.example.com/live/index.m3u8` |
| `CACHE_MAX_SIZE` | No | `500m` or `unlimited` | `unlimited` can exhaust the container filesystem; numeric caps are recommended. |
| `ORIGIN_TLS_VERIFY` | No | `on` | Set `off` only for a trusted origin with a certificate problem. |

### Cloudflared

| Variable | Required | Example |
|---|---:|---|
| `TUNNEL_TOKEN` | Yes | `<secret token>` |

Do not commit `.env` files or tunnel tokens. Set secrets in Railway variables.

## Deployment checklist

### 1. Prepare the repository

- [ ] Replace the example origin URL and public domain with real values.
- [ ] Confirm the origin accepts requests from Railway and supports the HLS paths you will expose.
- [ ] Confirm playlist URLs use the origin hostname if you expect router `sub_filter` rewriting.
- [ ] Push this repository to a Git provider connected to Railway, or deploy each service from the appropriate subdirectory.

### 2. Create Railway services

Create four services in one Railway project:

- [ ] `router` — root directory `router/`.
- [ ] `cache-a` — root directory `cache/`.
- [ ] `cache-b` — root directory `cache/`.
- [ ] `cloudflared` — root directory `cloudflared/`.

If using the Railway CLI, run the commands from each service directory or configure each service's root directory in the dashboard. Avoid deploying the monorepo root as a single service.

### 3. Configure non-persistent cache storage

This version intentionally uses **no Railway Volume**. Each cache node writes to its container filesystem at `/var/cache/hls`.

- [ ] Do **not** add a Railway volume.
- [ ] Keep `CACHE_MAX_SIZE=500m` unless you have verified a larger ephemeral-disk allocation for your Railway plan.
- [ ] Accept that cache data is lost after a restart or redeploy.
- [ ] Remember that cache contents are node-local; a cache miss on one node may still be a hit on another node.

The cache entrypoint creates `/var/cache/hls` and sets ownership to `www-data`. This is intentionally a non-persistent cache.

### 4. Configure variables

Router variables:

```env
ORIGIN_M3U8_URL=https://origin.example.com/live/sony/index.m3u8
EDGE_DOMAIN=tv.example.com
CACHE_NODES=${{cache-a.RAILWAY_PRIVATE_DOMAIN}},${{cache-b.RAILWAY_PRIVATE_DOMAIN}}
LB_STRATEGY=least_conn
HEALTH_CHECK_INTERVAL=10
HEALTH_CHECK_TIMEOUT=3
HEALTH_FAIL_THRESHOLD=2
HEALTH_RECOVERY_THRESHOLD=2
```

Cache-A and Cache-B variables:

```env
ORIGIN_M3U8_URL=https://origin.example.com/live/sony/index.m3u8
CACHE_MAX_SIZE=500m
ORIGIN_TLS_VERIFY=on
```

Cloudflared variables:

```env
TUNNEL_TOKEN=<your-cloudflare-tunnel-token>
```

Railway reference-variable names are case-sensitive and must match the actual service names. Verify the resolved value of `CACHE_NODES` in the router logs if node discovery does not work.

### 5. Configure Cloudflare Tunnel

In Cloudflare Zero Trust:

1. Open **Networks → Tunnels** and select the tunnel.
2. Add a public hostname such as `tv.example.com`.
3. Set the service type to `HTTP`.
4. Point the service to the router's private Railway address and port `8080`, for example:

```text
http://router-production-xxxx.railway.internal:8080
```

5. Confirm the tunnel connector is running and connected.
6. Configure TLS and DNS through Cloudflare for the public hostname.

### 6. Verify the deployment

Run these from a machine that can reach the public hostname:

```bash
# Router liveness
curl -fsS https://tv.example.com/health

# Router readiness; should report at least one healthy cache node
curl -fsS https://tv.example.com/ready

# Per-node state
curl -fsS https://tv.example.com/metrics/nodes

# Fetch a playlist and inspect the first lines
curl -fsS https://tv.example.com/live/sony/index.m3u8 | head -n 20

# Check cache behavior for a segment
curl -sSI https://tv.example.com/live/sony/segment000.ts | grep -i X-Cache-Status
curl -sSI https://tv.example.com/live/sony/segment000.ts | grep -i X-Cache-Status
```

The first segment request is normally `MISS` and a subsequent request may be `HIT`, provided the origin returned a cacheable `200` response and both requests reached the same cache node. With multiple nodes and load balancing, the second request can legitimately be a miss on a different node.

### 7. Inspect logs and failures

- [ ] Router logs show `initial_upstream_generated` with the expected node names.
- [ ] Router `/metrics/nodes` reports healthy nodes.
- [ ] Cache logs show `200` responses and `X-Cache-Status` values.
- [ ] Cloudflared logs show a connected tunnel.
- [ ] `nginx -t` succeeds during each container startup.
- [ ] Confirm the origin's response is not compressed when playlist rewriting is needed; the router disables upstream compression for this reason.

## Operational notes

- Router health checks call `http://<cache-node>:8080/health` concurrently. Nodes are removed after the configured failure threshold and restored after the recovery threshold.
- The router writes `/etc/nginx/conf.d/upstream.conf` and reloads Nginx when node health changes.
- Playlist rewriting only changes absolute `http://origin-host` and `https://origin-host` references to `https://EDGE_DOMAIN`. Relative playlist URLs are passed through unchanged.
- Media segments are cached for approximately the last 60 seconds; playlists remain cached for 2 seconds. Nginx's cache manager removes inactive objects asynchronously, so the actual disk usage may briefly differ from the configured limit.
- The cache disables TLS certificate verification to support arbitrary origins. For a controlled production origin, consider enabling certificate verification and installing the required CA chain instead.
- The current cache key is `$request_uri`, so query strings are included. Ensure origin query parameters do not contain secrets that should be stored in cache keys or logs.
- The control-plane endpoints are exposed through the public router hostname. Restrict `/metrics` and `/metrics/nodes` at the tunnel or with an authentication layer if they should not be public.
- Nginx reloads should be monitored. A failed reload leaves the previously running configuration in place, while the newly written upstream file remains on disk.

## Local configuration checks

Build the images from their service directories:

```bash
docker build -t edgestream-router ./router
docker build -t edgestream-cache ./cache
```

To test the generated configuration, provide environment variables and run the image. A full local multi-node test also requires a reachable origin and a Docker network with resolvable cache service names.

## Security recommendations before production

- [ ] Keep `TUNNEL_TOKEN` only in Railway's secret environment variables.
- [ ] Restrict administrative endpoints or put them behind Cloudflare Access.
- [ ] Set an explicit origin allowlist if the application evolves to accept user-provided URLs.
- [ ] Review cache-control behavior for authenticated or personalized content; this design assumes public HLS content.
- [ ] Pin the `cloudflared` image to a tested version instead of `latest` once the deployment is stable.
- [ ] Load-test the origin, ephemeral cache capacity, router connection limits, and Cloudflare Tunnel before a live event.
