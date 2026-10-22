#!/bin/sh
# Assert that a running xerj-sandbox container still matches the documented posture.
# Every check fails loudly; this script has no fix-it mode.
set -eu

NAME=${1:-xerj-sandbox}

fail() {
  echo "POSTURE FAIL: $1" >&2
  exit 1
}

docker inspect "$NAME" >/dev/null 2>&1 || fail "container '$NAME' not found"

# memory caps present and swap capped at the same value (self-kill, no swap-thrash)
mem=$(docker inspect -f '{{.HostConfig.Memory}}' "$NAME")
swap=$(docker inspect -f '{{.HostConfig.MemorySwap}}' "$NAME")
[ "$mem" != "0" ] || fail "no memory cap set"
[ "$swap" = "$mem" ] || fail "memory-swap != memory (swap-thrash protection off)"

# CPU cap present (2 CPUs)
[ "$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$NAME")" = "2000000000" ] \
  || fail "no CPU cap set (expected 2 CPUs)"

# root filesystem read-only, with an ephemeral tmpfs at /tmp
[ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$NAME")" = "true" ] \
  || fail "root filesystem is not read-only"
docker inspect -f '{{range $p, $v := .HostConfig.Tmpfs}}{{println $p}}{{end}}' "$NAME" |
  grep -qx "/tmp" || fail "no tmpfs at /tmp"

# published only on loopback: every binding's HostIp must be loopback (allowlist,
# so IPv6 wildcards, empty HostIp, and 0.0.0.0 all fail)
nonlo=$(docker inspect -f '{{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{println .HostIp}}{{end}}{{end}}' "$NAME" |
  grep -vxe '127.0.0.1' -e '::1' || true)
[ -z "$nonlo" ] || fail "non-loopback port binding found: $nonlo"

# telemetry opt-out present
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$NAME" |
  grep -qx "XERJ_DISABLE_FEEDBACK=1" || fail "XERJ_DISABLE_FEEDBACK=1 not set"

# never privileged, never can escalate, no docker socket
[ "$(docker inspect -f '{{.HostConfig.Privileged}}' "$NAME")" = "false" ] \
  || fail "container is privileged"
[ "$(docker inspect -f '{{.HostConfig.CapAdd}}' "$NAME")" = "[]" ] \
  || fail "extra capabilities added"
docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' "$NAME" |
  grep -q "docker.sock" && fail "docker socket is mounted"

# no-new-privileges on
[ "$(docker inspect -f '{{.HostConfig.SecurityOpt}}' "$NAME")" = "[no-new-privileges]" ] \
  || fail "no-new-privileges not set"

# running as the non-root user
[ "$(docker inspect -f '{{.Config.User}}' "$NAME")" = "10001" ] \
  || fail "not running as uid 10001"
# writable binds are only the named data volume; any directory bind must be ro
ro=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{println .Destination}}{{end}}{{end}}' "$NAME")
rwbinds=$(docker inspect -f '{{range .Mounts}}{{if and (eq .Type "bind") (ne .RW false)}}{{println .Destination}}{{end}}{{end}}' "$NAME")
[ -z "$rwbinds" ] || fail "writable directory bind(s) found: $rwbinds (binds must be read-only; data lives in the named volume)"

echo "posture OK: caps, loopback publish, telemetry off, unprivileged, ro binds, no socket"
[ -n "$ro" ] && echo "read-only binds: $ro" || true
