#!/usr/bin/env bats
# Unit tests for scripts/install.sh — the attestation verification policy.
#
# Strategy: put fake `curl` and `gh` first on PATH. The fake curl serves the
# release JSON ($FAKE_RELEASE_JSON) for API requests and a real fixture archive
# (plus its matching .sha256) for downloads, logging every URL; the fake gh
# logs its arguments and exits with $FAKE_GH_EXIT. That lets us assert when
# install.sh verifies the attestation, with which arguments, and that a failed
# verification stops the install.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/scripts/install.sh"

  # A release archive holding a `cccc` binary, and its checksum file.
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE/src"
  printf '#!/bin/sh\necho fake cccc\n' > "$FIXTURE/src/cccc"
  tar -czf "$FIXTURE/archive.tar.gz" -C "$FIXTURE/src" cccc
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$FIXTURE/archive.tar.gz" > "$FIXTURE/archive.sha256"
  else
    shasum -a 256 "$FIXTURE/archive.tar.gz" > "$FIXTURE/archive.sha256"
  fi

  FAKEBIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKEBIN"
  cat > "$FAKEBIN/curl" <<'EOF'
#!/usr/bin/env bash
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -H) shift ;;
    -*) ;;
    *) url="$1" ;;
  esac
  shift
done
echo "$url" >> "$CURL_LOG"
case "$out" in
  "") printf '%s\n' "$FAKE_RELEASE_JSON" ;;
  *.sha256) cp "$FIXTURE/archive.sha256" "$out" ;;
  *) cp "$FIXTURE/archive.tar.gz" "$out" ;;
esac
EOF
  cat > "$FAKEBIN/gh" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do echo "$a"; done > "$GH_LOG"
exit "${FAKE_GH_EXIT:-0}"
EOF
  chmod +x "$FAKEBIN/curl" "$FAKEBIN/gh"
  export PATH="$FAKEBIN:$PATH"

  export FIXTURE
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  : > "$CURL_LOG"
  export FAKE_RELEASE_JSON='{
  "tag_name": "v9.9.9",
  "body": "mentions \"immutable\": true in text",
  "immutable": true
}'

  export INPUT_VERSION=latest INPUT_REPOSITORY=moznion/cccc \
    INPUT_VERIFY_ATTESTATION=auto GH_TOKEN=dummy \
    RUNNER_OS=Linux RUNNER_ARCH=X64 RUNNER_TEMP="$BATS_TEST_TMPDIR/runner" \
    GITHUB_PATH="$BATS_TEST_TMPDIR/github_path" \
    GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
  : > "$GITHUB_PATH"
}

@test "auto verifies an immutable release with the release workflow as signer" {
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ "$(cat "$GH_LOG")" = "attestation
verify
cccc-v9.9.9-x86_64-unknown-linux-musl.tar.gz
--repo
moznion/cccc
--signer-workflow
moznion/cccc/.github/workflows/release-build.yml
--deny-self-hosted-runners" ]
  grep -q '^version=v9.9.9$' "$GITHUB_OUTPUT"
  # "latest" was resolved once and its JSON reused for the immutable check.
  [ "$(grep -c '^https://api.github.com/' "$CURL_LOG")" -eq 1 ]
}

@test "auto skips a mutable release, ignoring \"immutable\" in its body" {
  export FAKE_RELEASE_JSON='{
  "tag_name": "v9.9.9",
  "body": "mentions \"immutable\": true in text",
  "immutable": false
}'
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ ! -e "$GH_LOG" ]
  [[ "$output" == *"not an immutable release"* ]]
  grep -q '^version=v9.9.9$' "$GITHUB_OUTPUT"
}

@test "auto looks up a pinned version's release by its tag" {
  export INPUT_VERSION=v1.2.3
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  grep -q '^https://api.github.com/repos/moznion/cccc/releases/tags/v1.2.3$' "$CURL_LOG"
  grep -q '^cccc-v1.2.3-x86_64-unknown-linux-musl.tar.gz$' "$GH_LOG"
}

@test "false never verifies, and makes no API request for a pinned version" {
  export INPUT_VERIFY_ATTESTATION=false INPUT_VERSION=v1.2.3
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ ! -e "$GH_LOG" ]
  ! grep -q 'api.github.com' "$CURL_LOG"
}

@test "true verifies even a mutable release" {
  export INPUT_VERIFY_ATTESTATION=true FAKE_RELEASE_JSON='{"tag_name": "v9.9.9", "immutable": false}'
  run bash "$INSTALL"
  [ "$status" -eq 0 ]
  [ -e "$GH_LOG" ]
}

@test "a failed verification fails the install before it is put on PATH" {
  export FAKE_GH_EXIT=1
  run bash "$INSTALL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"attestation verification failed"* ]]
  [ ! -s "$GITHUB_PATH" ]
}

@test "a required verification without gh fails with a hint" {
  rm "$FAKEBIN/gh"
  # Hide any real gh: keep only the tools install.sh needs on PATH.
  TOOLS="$BATS_TEST_TMPDIR/tools"
  mkdir -p "$TOOLS"
  for t in bash env cat cp mkdir chmod awk grep sed tar gzip sha256sum shasum perl; do
    p=$(command -v "$t" || true)
    [ -n "$p" ] && ln -sf "$p" "$TOOLS/$t"
  done
  PATH="$FAKEBIN:$TOOLS" run bash "$INSTALL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"verify-attestation: false"* ]]
  [ ! -s "$GITHUB_PATH" ]
}

@test "an unknown verify-attestation value is rejected" {
  export INPUT_VERIFY_ATTESTATION=yes
  run bash "$INSTALL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be auto, true, or false"* ]]
}
