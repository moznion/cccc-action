#!/usr/bin/env bash
# Run cccc as a complexity gate over the requested paths.
#
# Inputs (environment variables, set by action.yml):
#   BIN                  Absolute path to the installed cccc binary.
#   INPUT_PATH           Whitespace-separated files/directories to analyze.
#   INPUT_NO_CONFIG      Boolean flag ("true"/...).
#   INPUT_CONFIG / INPUT_TOP_COGNITIVE / INPUT_TOP_CYCLOMATIC
#                                                  Optional valued options.
#   INPUT_ARGS           Extra raw arguments appended verbatim.
#   INPUT_OUTPUT_FILE    If set, also write output to this file.
#   CCCC_CACHE_FILE      Resolved results-cache path, "" when caching is off
#                        (from resolve-cache.sh; only used for reporting).
#   GITHUB_OUTPUT        Step-output sink (exit-code, cache-file-exists).
#
# Analysis behavior (languages, excludes, extensions, complexity thresholds,
# ignore/jobs, table output) lives in cccc's config file (cccc.toml); only the
# command-line-only knobs are handled here. Use INPUT_ARGS for anything else.
#
# This step always exits 0: cccc's exit code is published as the `exit-code`
# step output and re-raised by the action's final gate step, so a failing gate
# cannot skip the cache-save step that runs in between.
set -euo pipefail

args=()
add_opt()  { if [ -n "$2" ];        then args+=("$1" "$2"); fi; }
add_flag() { if [ "$2" = "true" ];  then args+=("$1");      fi; }

add_flag  --no-config      "$INPUT_NO_CONFIG"
add_opt   --config         "$INPUT_CONFIG"
add_opt   --top-cognitive  "$INPUT_TOP_COGNITIVE"
add_opt   --top-cyclomatic "$INPUT_TOP_CYCLOMATIC"
# No cache flags are injected here: whether (and where) to cache is resolved
# by cccc from its own config, exactly as in a local run. resolve-cache.sh
# asked cccc the same question up front so restore/save address the same file.

# Extra raw args and target paths (whitespace-separated).
read -r -a extra <<< "$INPUT_ARGS"
read -r -a paths <<< "$INPUT_PATH"

set -- "${args[@]+"${args[@]}"}" "${extra[@]+"${extra[@]}"}" "${paths[@]+"${paths[@]}"}"
echo "+ cccc $*"
set +e
if [ -n "$INPUT_OUTPUT_FILE" ]; then
  "$BIN" "$@" | tee "$INPUT_OUTPUT_FILE"
  code=${PIPESTATUS[0]}
else
  "$BIN" "$@"
  code=$?
fi
set -e

{
  echo "exit-code=$code"
  # Lets the save step skip cleanly when no cache file was written (e.g. cccc
  # bailed out before analysis).
  if [ -n "$CCCC_CACHE_FILE" ] && [ -f "$CCCC_CACHE_FILE" ]; then
    echo "cache-file-exists=true"
  fi
} >> "$GITHUB_OUTPUT"
