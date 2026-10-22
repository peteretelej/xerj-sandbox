# Pin binary version AND both checksums together; they are one fact.
# Checksums come from the GitHub release API asset digests for the musl static builds.
ARG XERJ_VERSION=1.0.0-rc.98
ARG XERJ_X86_64_SHA256=550712e9e3c49e4f6cb4602b55a05ce52c3c1ee725ed49431f5d68652bc710d5
ARG XERJ_AARCH64_SHA256=fcf07ca828c8ea2dd6d17e0819649dc6a4580d6f27ba29554c972328f9c6ee9e

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
RUN adduser -D -H -u 10001 xerj \
  && mkdir -p /data \
  && chown xerj:xerj /data
USER xerj
ENV XERJ_DISABLE_FEEDBACK=1
VOLUME /data
EXPOSE 9200
ENTRYPOINT ["/usr/local/bin/xerj"]
CMD ["--data-dir", "/data"]
