A newer XERJ release exists upstream. The pin in this repo is deliberate:
bumping is a review decision, not an auto-update.

- Read the upstream release notes/changelog for this version.
- Take `XERJ_VERSION` and both `XERJ_*_SHA256` values from the release's own
  asset digests (`https://api.github.com/repos/xerj-org/xerj/releases/latest`),
  never from a mirror.
- Change all three `ARG`s in one commit.
- A checksum failure at build time is a stop sign: confirm the new value comes
  from the project's own release and the changelog explains the change (see
  SAFETY.md upgrade policy) before touching it.
- After the bump, rerun `scripts/smoke-test.sh` and `scripts/posture-drift-test.sh`.
