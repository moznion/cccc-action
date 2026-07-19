#!/usr/bin/env bats
# Unit tests for scripts/resolve-cache.sh — cache-location resolution.
#
# Strategy: a fake cccc ($BIN) that logs its arguments and prints
# $FAKE_CACHE_PATH when asked for --print-cache-file, standing in for cccc's
# config-driven resolution.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RESOLVE="$REPO_ROOT/scripts/resolve-cache.sh"

  FAKEBIN="$BATS_TEST_TMPDIR/fake-cccc"
  cat > "$FAKEBIN" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do echo "$a" >> "$ARGS_LOG"; done
printf '%s' "${FAKE_CACHE_PATH:-}"
if [ -n "${FAKE_CACHE_PATH:-}" ]; then echo; fi
EOF
  chmod +x "$FAKEBIN"
  export BIN="$FAKEBIN"
  export ARGS_LOG="$BATS_TEST_TMPDIR/args_log"

  export INPUT_PATH="" INPUT_CONFIG="" INPUT_NO_CONFIG="" INPUT_ARGS="" \
    GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
}

@test "asks cccc via --print-cache-file and publishes the path" {
  export FAKE_CACHE_PATH="/abs/dir/.cccc.cache"
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  grep -q -- '--print-cache-file' "$ARGS_LOG"
  grep -q '^file=/abs/dir/.cccc.cache$' "$GITHUB_OUTPUT"
}

@test "a relative path is absolutized against the working directory" {
  export FAKE_CACHE_PATH="rel.cache"
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  grep -q "^file=$PWD/rel.cache$" "$GITHUB_OUTPUT"
}

@test "caching disabled: publishes an empty file output" {
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  grep -q '^file=$' "$GITHUB_OUTPUT"
  [[ "$output" == *"disabled"* ]]
}

@test "config selection and extra args are forwarded to cccc" {
  export INPUT_NO_CONFIG=true INPUT_CONFIG="" INPUT_ARGS="--cache --jobs 2"
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  grep -q -- '^--no-config$' "$ARGS_LOG"
  grep -q -- '^--cache$' "$ARGS_LOG"
  grep -q -- '^--jobs$' "$ARGS_LOG"
}

@test "key-part is a stable 12-hex discriminator that tracks the analysis identity" {
  export INPUT_PATH="src"
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  first="$(grep '^key-part=' "$GITHUB_OUTPUT" | cut -d= -f2)"
  [[ "$first" =~ ^[0-9a-f]{12}$ ]]

  : > "$GITHUB_OUTPUT"
  run bash "$RESOLVE"
  same="$(grep '^key-part=' "$GITHUB_OUTPUT" | cut -d= -f2)"
  [ "$same" = "$first" ]

  : > "$GITHUB_OUTPUT"
  export INPUT_PATH="lib"
  run bash "$RESOLVE"
  other="$(grep '^key-part=' "$GITHUB_OUTPUT" | cut -d= -f2)"
  [ "$other" != "$first" ]
}
