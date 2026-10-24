#!/bin/sh
# End-to-end behavioral smoke test: build the image, start a container with the
# full posture, index a tiny corpus, and query it over the loopback API.
# Runs under a distinct container name and host port so it never touches a
# real xerj-sandbox node; cleans up after itself.
set -eu

cd "$(dirname "$0")/.."

command -v docker >/dev/null || { echo "smoke: docker not found" >&2; exit 1; }
command -v curl >/dev/null || { echo "smoke: curl not found" >&2; exit 1; }

NAME=xerj-sandbox-smoke
PORT=19200
CORPUS=$(mktemp -d)
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; docker volume rm "$NAME-data" >/dev/null 2>&1 || true; rm -rf "$CORPUS"' EXIT

# fixture corpus with terms that exist nowhere else
mkdir -p "$CORPUS/demo"
cat > "$CORPUS/demo/README.md" <<EOF
# smoke corpus

This fixture exists only for the smoke test. Its unique marker term is
QUILLFENWICK and it appears nowhere else.
EOF
cat > "$CORPUS/demo/marker.go" <<'EOF'
package demo

// ParseQuillFenwick is the smoke-test marker function.
func ParseQuillFenwick(input string) string { return input }
EOF
# the container reads this bind as uid 10001: mktemp starts at 0700
chmod 755 "$CORPUS" "$CORPUS/demo"
chmod 644 "$CORPUS/demo/README.md" "$CORPUS/demo/marker.go"

echo "smoke: build + start + posture check"
XERJ_SANDBOX_NAME="$NAME" XERJ_SANDBOX_PORT="$PORT" scripts/dev-container.sh \
  --mount "type=bind,src=$CORPUS,dst=/corpus,readonly"

KEY=$(docker exec "$NAME" cat /data/admin.key)
AUTH="Authorization: ApiKey $KEY"
BASE="http://127.0.0.1:$PORT"

echo "smoke: auth must reject unauthenticated probes"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")
if [ "$code" != "401" ]; then
  echo "smoke FAIL: unauthenticated probe returned $code, want 401" >&2
  exit 1
fi

echo "smoke: index the corpus"
docker exec -e XERJ_API_KEY="$KEY" "$NAME" xerj autoindex /corpus

echo "smoke: query for the marker term"
hit=""
i=0
while [ "$i" -lt 15 ]; do
  if curl -s "$BASE/_search" -H "$AUTH" -H 'Content-Type: application/json' \
      -d '{"query":{"query_string":{"query":"QUILLFENWICK"}}}' | grep -q QUILLFENWICK; then
    hit=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ -z "$hit" ]; then
  echo "smoke FAIL: marker term never came back from _search" >&2
  exit 1
fi

echo "smoke OK: build, posture, auth, index, query"
