# Pin binary version AND both checksums together; they are one fact.
# Checksums come from the GitHub release API asset digests for the musl static builds.
ARG XERJ_VERSION=1.0.0-rc.99
ARG XERJ_X86_64_SHA256=f29dd2f9f3dfa4e3eba24401fb52f7a4ed79773a9c3e303d5979745f5c827526
ARG XERJ_AARCH64_SHA256=1347b81d2b18cf74beefede73146008f15217455abcc7281c177fc0443603364

FROM alpine:3.20 AS fetch
ARG XERJ_VERSION
ARG XERJ_X86_64_SHA256
ARG XERJ_AARCH64_SHA256
RUN apk add --no-cache curl
RUN case "$(uname -m)" in \
      x86_64)  arch=x86_64;  want="$XERJ_X86_64_SHA256"  ;; \
      aarch64) arch=aarch64; want="$XERJ_AARCH64_SHA256" ;; \
      *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac \
  && curl -fsSL -o /tmp/xerj.tar.gz \
       "https://github.com/xerj-org/xerj/releases/download/v${XERJ_VERSION}/xerj-${XERJ_VERSION}-${arch}-unknown-linux-musl.tar.gz" \
  && echo "${want}  /tmp/xerj.tar.gz" | sha256sum -c - \
  && mkdir -p /tmp/out /fetch \
  && tar -xzf /tmp/xerj.tar.gz -C /tmp/out \
  && find /tmp/out -type f -name xerj -exec mv {} /fetch/xerj \; \
  && chmod 0755 /fetch/xerj \
  && test -x /fetch/xerj

FROM alpine:3.20
COPY --from=fetch /fetch/xerj /usr/local/bin/xerj
COPY xerj.toml /etc/xerj/xerj.toml
RUN adduser -D -H -u 10001 xerj \
  && mkdir -p /data \
  && chown xerj:xerj /data
USER 10001
ENV XERJ_DISABLE_FEEDBACK=1
# HOME lives on the named volume so persistent tool state (hub pack cache,
# autoindex resume journals) stays inside the posture boundary: the volume is
# the only writable path, and nothing lands on the read-only root filesystem.
ENV HOME=/data
# Hard engine memory cap (see xerj.toml): the Auto limiter OOM-killed the
# container at every cgroup size once hub packs were restored; an explicit
# 3 GB process cap keeps the self-kill predictable and the boundary intact.
ENV XERJ_CONFIG=/etc/xerj/xerj.toml
# Declared because the node binds all interfaces INSIDE the container: the
# container network namespace is the isolation boundary and the host publish is
# pinned to 127.0.0.1 (posture-check fails on any non-loopback host binding).
# Upstream requires this explicit declaration for a non-loopback bind without
# TLS; the API key never crosses a real network interface.
ENV XERJ_ALLOW_INSECURE_NETWORK_BIND=true
VOLUME /data
EXPOSE 9200
ENTRYPOINT ["/usr/local/bin/xerj"]
CMD ["--data-dir", "/data", "--bind", "0.0.0.0"]
