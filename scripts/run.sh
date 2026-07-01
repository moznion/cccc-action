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
#
# Analysis behavior (languages, excludes, extensions, complexity thresholds,
# ignore/jobs, table output) lives in cccc's config file (cccc.toml); only the
# command-line-only knobs are handled here. Use INPUT_ARGS for anything else.
set -euo pipefail

args=()
add_opt()  { if [ -n "$2" ];        then args+=("$1" "$2"); fi; }
add_flag() { if [ "$2" = "true" ];  then args+=("$1");      fi; }

add_flag  --no-config      "$INPUT_NO_CONFIG"
add_opt   --config         "$INPUT_CONFIG"
add_opt   --top-cognitive  "$INPUT_TOP_COGNITIVE"
add_opt   --top-cyclomatic "$INPUT_TOP_CYCLOMATIC"

# Extra raw args and target paths (whitespace-separated).
read -r -a extra <<< "$INPUT_ARGS"
read -r -a paths <<< "$INPUT_PATH"

set -- "${args[@]+"${args[@]}"}" "${extra[@]+"${extra[@]}"}" "${paths[@]+"${paths[@]}"}"
echo "+ cccc $*"
if [ -n "$INPUT_OUTPUT_FILE" ]; then
  "$BIN" "$@" | tee "$INPUT_OUTPUT_FILE"
else
  "$BIN" "$@"
fi
