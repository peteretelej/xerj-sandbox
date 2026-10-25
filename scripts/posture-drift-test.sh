#!/bin/sh
# Prove scripts/posture-check.sh actually rejects drift: create containers with
# one posture control missing or weakened and assert the check fails on each.
# Containers are created, never started: every check inspects config only, so
# XERJ itself does not run here. Each case spells out its full config because
# docker ACCUMULATES repeatable flags (--security-opt, -e, -v, --cap-add):
# appending to a shared baseline cannot express "control absent".
set -eu

cd "$(dirname "$0")/.."

IMAGE=xerj-sandbox
NAME=xerj-sandbox-drift
PORT=19201
rc=0

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -t "$IMAGE" .
fi

BINDSRC=$(mktemp -d)
cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker volume rm xerj-sandbox-drift-data >/dev/null 2>&1 || true
  rm -rf "$BINDSRC"
}
trap cleanup EXIT

# full conforming config, in the same shape dev-container.sh passes
conforming() {
  printf '%s ' \
    --cpus 2 --memory 4g --memory-swap 4g \
    --read-only --tmpfs /tmp \
    --security-opt no-new-privileges \
    -e XERJ_CONFIG=/etc/xerj/xerj.toml \
    -e XERJ_DISABLE_FEEDBACK=1 \
    -p "127.0.0.1:$PORT:9200" \
    -v xerj-sandbox-drift-data:/data
}

expect_fail() {
  desc=$1; shift
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker create --name "$NAME" "$@" "$IMAGE" >/dev/null
  if scripts/posture-check.sh "$NAME" >/dev/null 2>&1; then
    echo "drift FAIL: posture-check passed with $desc" >&2
    rc=1
  else
    echo "drift ok: rejected - $desc"
  fi
}

echo "drift: control (conforming container must pass)"
docker rm -f "$NAME" >/dev/null 2>&1 || true
# word splitting intended: conforming() emits one flag per word
# shellcheck disable=SC2046
docker create --name "$NAME" $(conforming) "$IMAGE" >/dev/null
if scripts/posture-check.sh "$NAME" >/dev/null 2>&1; then
  echo "drift ok: control passes"
else
  echo "drift FAIL: posture-check rejected a conforming control container" >&2
  rc=1
fi

expect_fail "no memory cap" \
  --cpus 2 \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "memory-swap unlimited instead of capped at memory" \
  --cpus 2 --memory 4g --memory-swap -1 \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "no CPU cap" \
  --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "writable root filesystem" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "no tmpfs at /tmp" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "published beyond loopback" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "telemetry opt-out overridden to empty" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK= \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "extra capability added" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  --cap-add NET_BIND_SERVICE \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "no-new-privileges missing" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "running as root" \
  --user 0 \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

expect_fail "writable directory bind" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data \
  -v "$BINDSRC:/hostdata"

expect_fail "docker socket mounted" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data \
  -v /var/run/docker.sock:/var/run/docker.sock

expect_fail "host network mode removes the namespace boundary" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data \
  --network host

expect_fail "publish-all ports bypasses the explicit allowlist" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -v xerj-sandbox-drift-data:/data \
  -P

expect_fail "host pid namespace shared" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data \
  --pid host

expect_fail "host ipc namespace shared" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG=/etc/xerj/xerj.toml \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data \
  --ipc host

expect_fail "engine memory cap unwired (XERJ_CONFIG overridden to empty)" \
  --cpus 2 --memory 4g --memory-swap 4g \
  --read-only --tmpfs /tmp \
  --security-opt no-new-privileges \
  -e XERJ_CONFIG= \
  -e XERJ_DISABLE_FEEDBACK=1 \
  -p "127.0.0.1:$PORT:9200" \
  -v xerj-sandbox-drift-data:/data

if [ "$rc" != "0" ]; then
  echo "drift FAIL: one or more drift cases were not rejected" >&2
  exit 1
fi
echo "drift OK: every weakened config was rejected"
