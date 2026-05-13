# Deploy CouchMC web to linloir.cn

## Topology

- Host: `ubuntu@175.178.63.38:22417` (Tencent Cloud, Ubuntu 24.04)
- Caddy runs as a Docker container with `network_mode: host`
  (`linloir/caddy-git-dns:latest`, see `~/docker_caddy/`).
- Caddyfile lives on the host at
  `/home/ubuntu/docker_caddy/data/caddyfile/Caddyfile` and is mounted
  into the container at `/etc/caddy/Caddyfile`.
- Each application is its own Docker container exposing a private
  port on `127.0.0.1`; Caddy reverse-proxies the public hostname to
  that port.

| Domain                  | Container         | Internal port |
| ----------------------- | ----------------- | ------------- |
| `infilearn.linloir.cn`  | `infi-learn-web`  | `127.0.0.1:23000` |
| `couchmc.linloir.cn`    | `couchmc-web`     | `127.0.0.1:23010` |

The CouchMC source on the server lives at
`/home/ubuntu/couchmc-web/_release/`.

## First-time deploy (already done)

1. Build a Next.js standalone bundle in a Dockerfile (this folder).
2. Sync the source tree to `/home/ubuntu/couchmc-web/_release/`.
3. `cd /home/ubuntu/couchmc-web/_release && sudo docker compose build`
4. `sudo docker compose up -d`
5. `bash /home/ubuntu/couchmc-web/deploy-caddy.sh`
   (appends the `couchmc.linloir.cn` block to the Caddyfile and asks
   the running Caddy container to graceful-reload, no other site is
   restarted).

## Pushing an update

From a Windows PowerShell in `web/`:

```powershell
# 1. Stage source without node_modules / .next
$staging = "$env:TEMP\couchmc-web-deploy"
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Path $staging | Out-Null
$excludes = @('node_modules', '.next', 'out', 'build', 'dist', '.git')
Get-ChildItem -Force | Where-Object { $excludes -notcontains $_.Name } |
  ForEach-Object { Copy-Item -Recurse -Path $_.FullName -Destination $staging }

# 2. Tar + scp to the server
$tarball = "$env:TEMP\couchmc-web-deploy.tar.gz"
if (Test-Path $tarball) { Remove-Item $tarball }
Push-Location $staging; tar -czf $tarball .; Pop-Location
ssh -p 22417 ubuntu@175.178.63.38 "rm -rf /home/ubuntu/couchmc-web/_incoming && mkdir -p /home/ubuntu/couchmc-web/_incoming"
scp -P 22417 $tarball ubuntu@175.178.63.38:/home/ubuntu/couchmc-web/_incoming/source.tar.gz

# 3. Replace the release directory and rebuild
ssh -p 22417 ubuntu@175.178.63.38 @"
set -e
cd /home/ubuntu/couchmc-web
rm -rf _release
mkdir _release
tar -xzf _incoming/source.tar.gz -C _release
cd _release
sudo docker compose build
sudo docker compose up -d
sudo docker image prune -f
"@
```

(`docker compose up -d` will pick up the new image and replace the
container with zero-downtime if Docker Compose is recent enough; if
you want a hard restart instead, run `sudo docker compose down && sudo docker compose up -d`.)

## Caddy notes

- `deploy-caddy.sh` is idempotent — it only appends the
  `couchmc.linloir.cn` block once and reloads Caddy in place.
- Reload uses `caddy reload --config /etc/caddy/Caddyfile` so other
  sites (e.g. `infilearn.linloir.cn`) keep their listening sockets.
- TLS uses Cloudflare DNS-01 challenge; the API token is in
  `/home/ubuntu/docker_caddy/.env` as `CF_API_TOKEN`. The domain
  `couchmc.linloir.cn` already resolves to this host's public IP.

## Health checks

```bash
# Container internal
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:23010/

# Through Caddy (HTTPS) on the host
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --resolve couchmc.linloir.cn:443:127.0.0.1 https://couchmc.linloir.cn/

# Public
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' https://couchmc.linloir.cn/
```
