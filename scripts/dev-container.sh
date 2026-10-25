#!/bin/sh
# Build, recreate, and health-check the sandboxed XERJ container.
# The safety posture is hardcoded here on purpose: do not add flags that weaken it
# (host publishing, --insecure, writable corpus mounts, privileged mode).
set -eu

# XERJ_SANDBOX_NAME / XERJ_SANDBOX_PORT override the container name and host
# port (smoke-test uses both to run beside a real node); posture values never
# change.
NAME=${XERJ_SANDBOX_NAME:-xerj-sandbox}
PORT=${XERJ_SANDBOX_PORT:-9200}

cd "$(dirname "$0")/.."
docker build -t "$NAME" .

docker rm -f "$NAME" 2>/dev/null || true

# extra args (e.g. --mount type=bind,src=...,dst=/corpora,readonly) pass through
# shellcheck disable=SC2086
# 4 GB with the engine-side limits in xerj.toml serves the full multi-pack
# corpus at a few hundred MB on rc.99 (which fixed the rc.98 growth that
# outgrew every cap - upstream issues xerj-org/xerj#2238 and
# xerj-org/xerj#1940). The engine cap is the binding control; keep it wired.
docker run -d --name "$NAME" \
  --cpus 2 \
  --memory 4g \
  --memory-swap 4g \
  --read-only \
  --tmpfs /tmp \
  --security-opt no-new-privileges \
  -p "127.0.0.1:${PORT}:9200" \
  -v "${NAME}-data:/data" \
  "$@" \
  "$NAME"

echo "waiting for the node (auth is on, so a 401 means up)..."
i=0
while [ "$i" -lt 60 ]; do
  code=$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" || true)
  if [ "$code" = "401" ]; then
    echo "up: http://127.0.0.1:${PORT} (auth on)"
    scripts/posture-check.sh "$NAME"
    echo "admin key (in the container's named volume):"
    echo "  docker exec $NAME cat /data/admin.key"
    exit 0
  fi
  if [ "$code" = "200" ]; then
    echo "POSTURE FAIL: the node answered 200 without a key; auth is off" >&2
    docker logs --tail 20 "$NAME" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

echo "container did not become healthy in 60s; logs:" >&2
docker logs --tail 50 "$NAME" >&2
exit 1
