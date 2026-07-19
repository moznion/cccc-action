#!/usr/bin/env bash
# Resolve the results-cache location for this analysis by asking cccc itself.
#
# Whether to cache lives in cccc.toml (`cache = true`) — the same single
# source of truth local runs use — not in an action input. This step asks
# `cccc --print-cache-file` (with the same config selection and extra args the
# run step will use, so `--cache`/`--no-cache` overrides via `args` are
# honored) and publishes what the persistence steps need.
#
# Inputs (environment variables, set by action.yml):
#   BIN                Absolute path to the installed cccc binary.
#   INPUT_CONFIG / INPUT_NO_CONFIG    Config-file selection (as for run.sh).
#   INPUT_ARGS         Extra raw arguments, forwarded verbatim.
#   INPUT_PATH         Analyzed paths; only feeds the key discriminator.
#   GITHUB_OUTPUT      Step-output sink.
#
# Outputs:
#   file      Absolute path of the results cache; empty when caching is off.
#   key-part  Stable discriminator for the actions/cache key, derived from
#             what is analyzed and how — jobs caching different analyses of
#             the same repository get different keys instead of thrashing a
#             shared one.
set -euo pipefail

args=()
add_opt()  { if [ -n "$2" ];        then args+=("$1" "$2"); fi; }
add_flag() { if [ "$2" = "true" ];  then args+=("$1");      fi; }

add_flag  --no-config "$INPUT_NO_CONFIG"
add_opt   --config    "$INPUT_CONFIG"
read -r -a extra <<< "$INPUT_ARGS"

file="$("$BIN" --print-cache-file "${args[@]+"${args[@]}"}" "${extra[@]+"${extra[@]}"}")"
# actions/cache resolves relative paths against the workspace, which is only
# right when the working directory is the workspace root — absolutize instead.
if [ -n "$file" ]; then
  case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
fi

hash_input="$INPUT_PATH|$INPUT_CONFIG|$INPUT_NO_CONFIG|$INPUT_ARGS"
if command -v sha256sum > /dev/null 2>&1; then
  key_part="$(printf '%s' "$hash_input" | sha256sum | cut -c1-12)"
else
  key_part="$(printf '%s' "$hash_input" | shasum -a 256 | cut -c1-12)"
fi

{
  echo "file=$file"
  echo "key-part=$key_part"
} >> "$GITHUB_OUTPUT"
echo "results cache: ${file:-disabled}"
