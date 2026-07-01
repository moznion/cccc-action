#!/usr/bin/env bats
# Unit tests for scripts/run.sh — the argument-assembly logic.
#
# Strategy: replace the cccc binary ($BIN) with a fake that prints how many
# arguments it received and each argument on its own line. That lets us assert
# exactly which flags/options/paths run.sh forwarded, and that each token is
# passed as a separate argument (i.e. shell quoting is correct).
#
# Analysis behavior (languages, excludes, extensions, thresholds, ...) is
# configured in cccc.toml, not via action inputs, so run.sh only assembles the
# command-line-only knobs plus raw args and paths.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUN="$REPO_ROOT/scripts/run.sh"

  FAKEBIN="$BATS_TEST_TMPDIR/fake-cccc"
  cat > "$FAKEBIN" <<'EOF'
#!/usr/bin/env bash
echo "ARGC=$#"
for a in "$@"; do echo "ARG=$a"; done
EOF
  chmod +x "$FAKEBIN"
  export BIN="$FAKEBIN"

  # run.sh uses `set -u`, so every input must be defined (empty by default).
  export INPUT_PATH="" INPUT_CONFIG="" INPUT_NO_CONFIG="" \
    INPUT_TOP_COGNITIVE="" INPUT_TOP_CYCLOMATIC="" \
    INPUT_ARGS="" INPUT_OUTPUT_FILE=""
}

@test "no inputs: invokes the binary with zero arguments" {
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARGC=0"* ]]
}

@test "--no-config is added only when set to \"true\"" {
  export INPUT_NO_CONFIG=true
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARG=--no-config"* ]]
}

@test "--no-config set to \"false\" is not added" {
  export INPUT_NO_CONFIG=false
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ARG=--no-config"* ]]
}

@test "an explicit config path is forwarded" {
  export INPUT_CONFIG="cfg/cccc.toml" INPUT_PATH="src"
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARG=--config"* ]]
  [[ "$output" == *"ARG=cfg/cccc.toml"* ]]
}

@test "valued options pass the name and value as separate arguments" {
  export INPUT_TOP_COGNITIVE=10 INPUT_TOP_CYCLOMATIC=5
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARG=--top-cognitive"* ]]
  [[ "$output" == *"ARG=10"* ]]
  [[ "$output" == *"ARG=--top-cyclomatic"* ]]
  [[ "$output" == *"ARG=5"* ]]
}

@test "an empty valued option is omitted entirely" {
  export INPUT_TOP_COGNITIVE="" INPUT_PATH="src"
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ARG=--top-cognitive"* ]]
}

@test "multiple whitespace-separated paths become separate arguments" {
  export INPUT_PATH="src lib test"
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARG=src"* ]]
  [[ "$output" == *"ARG=lib"* ]]
  [[ "$output" == *"ARG=test"* ]]
}

@test "extra raw args are split and appended" {
  export INPUT_ARGS="--max-cognitive 15" INPUT_PATH="src"
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ARG=--max-cognitive"* ]]
  [[ "$output" == *"ARG=15"* ]]
  [[ "$output" == *"ARG=src"* ]]
}

@test "output-file receives a copy of the binary output" {
  out="$BATS_TEST_TMPDIR/result.txt"
  export INPUT_OUTPUT_FILE="$out" INPUT_TOP_COGNITIVE=3
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [ -f "$out" ]
  grep -q "ARG=--top-cognitive" "$out"
}

@test "the assembled command line is echoed for visibility" {
  export INPUT_TOP_COGNITIVE=3
  run bash "$RUN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ cccc"* ]]
}
