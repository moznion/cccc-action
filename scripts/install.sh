#!/usr/bin/env bash
# Install the cccc binary from a GitHub release and expose it on PATH.
#
# Inputs (environment variables, set by action.yml):
#   INPUT_VERSION     Release tag to install, or "latest".
#   INPUT_REPOSITORY  Repository to fetch the release from.
#   INPUT_VERIFY_ATTESTATION  "auto", "true", or "false" (see below).
#   GH_TOKEN          Optional token for the GitHub API.
#   RUNNER_OS / RUNNER_ARCH / RUNNER_TEMP   Provided by the runner.
#   GITHUB_PATH / GITHUB_OUTPUT             Provided by the runner.
set -euo pipefail

repo="$INPUT_REPOSITORY"

# Whether to verify the downloaded archive's build provenance attestation:
#   true   always (fails for releases published without one),
#   false  never (the SHA-256 checksum is still verified),
#   auto   when the release is immutable. cccc attests every release asset
#          since it enabled immutable releases, so an immutable release
#          without a valid attestation means the asset is not what the release
#          workflow built, while older (mutable) releases have none to verify.
verify="${INPUT_VERIFY_ATTESTATION:-auto}"
case "$verify" in
  auto|true|false) ;;
  *)
    echo "::error::verify-attestation must be auto, true, or false: '$verify'" >&2
    exit 1 ;;
esac

# Map the runner OS/arch to the release target triple.
case "$RUNNER_OS-$RUNNER_ARCH" in
  Linux-X64)    target=x86_64-unknown-linux-musl ;;
  Linux-ARM64)  target=aarch64-unknown-linux-musl ;;
  macOS-X64)    target=x86_64-apple-darwin ;;
  macOS-ARM64)  target=aarch64-apple-darwin ;;
  Windows-X64)  target=x86_64-pc-windows-msvc ;;
  *)
    echo "::error::unsupported runner: $RUNNER_OS/$RUNNER_ARCH" >&2
    exit 1 ;;
esac

# Authenticate every github.com / api.github.com request when a token is
# available. This avoids the unauthenticated rate limit, which GitHub enforces
# on shared CI egress IPs by returning 404 (not 403) for release-asset
# downloads — the symptom that breaks installs from runners.
auth=()
if [ -n "${GH_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer $GH_TOKEN")
fi

# Print the release JSON at releases/<$1> (e.g. "latest", "tags/v1.0.0").
fetch_release() {
  curl -fsSL "${auth[@]}" -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$repo/releases/$1"
}

# Resolve the release tag.
tag="$INPUT_VERSION"
body=""
if [ -z "$tag" ] || [ "$tag" = latest ]; then
  body=$(fetch_release latest)
  # Feed grep from a here-string rather than `printf '%s' "$body" | grep -m1`.
  # `grep -m1` exits as soon as it finds the first match and closes the pipe;
  # the bash `printf` builtin, still writing the (large) body, then hits a
  # "write error: Broken pipe" and exits non-zero, which under `set -o pipefail`
  # fails the whole script. A here-string has no upstream writer to break.
  tag=$(grep -m1 '"tag_name"' <<<"$body" \
    | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
fi
if [ -z "$tag" ]; then
  echo "::error::could not resolve a cccc release tag" >&2
  exit 1
fi

case "$RUNNER_OS" in
  Windows) archive_ext=zip;    binname=cccc.exe ;;
  *)       archive_ext=tar.gz; binname=cccc ;;
esac

# The checksum asset replaces the archive extension with ".sha256" (e.g.
# cccc-<tag>-<target>.sha256), it does not append to the full archive name.
stem="cccc-$tag-$target"
archive="$stem.$archive_ext"
sha_file="$stem.sha256"
base="https://github.com/$repo/releases/download/$tag"
workdir="$RUNNER_TEMP/cccc"
mkdir -p "$workdir"
cd "$workdir"

echo "Downloading $base/$archive"
curl -fsSL "${auth[@]}" -o "$archive" "$base/$archive"
curl -fsSL "${auth[@]}" -o "$sha_file" "$base/$sha_file"

# Verify the SHA-256 checksum.
expected=$(awk '{print $1}' "$sha_file")
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$archive" | awk '{print $1}')
else
  actual=$(shasum -a 256 "$archive" | awk '{print $1}')
fi
if [ "$expected" != "$actual" ]; then
  echo "::error::checksum mismatch for $archive (expected $expected, got $actual)" >&2
  exit 1
fi

if [ "$verify" = auto ]; then
  if [ -z "$body" ]; then
    body=$(fetch_release "tags/$tag")
  fi
  # The top-level `"immutable": true` of the release object; a release body
  # mentioning it is a JSON string, where its quotes are escaped.
  if grep -Eq '"immutable"[[:space:]]*:[[:space:]]*true' <<<"$body"; then
    verify=true
  else
    echo "::notice::cccc $tag is not an immutable release; skipping its attestation verification (the checksum is verified)"
    verify=false
  fi
fi

# Verify that the archive was built by cccc's release workflow on a
# GitHub-hosted runner: a checksum alone only proves the archive matches the
# .sha256 file next to it, which whoever replaced one could replace too.
if [ "$verify" = true ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "::error::verifying the attestation of $archive needs the GitHub CLI (gh); install it or set verify-attestation: false" >&2
    exit 1
  fi
  if ! gh attestation verify "$archive" \
      --repo "$repo" \
      --signer-workflow "$repo/.github/workflows/release-build.yml" \
      --deny-self-hosted-runners; then
    echo "::error::attestation verification failed for $archive" >&2
    exit 1
  fi
  echo "Verified the build provenance attestation of $archive"
fi

# Extract. The Windows runner's bash uses GNU tar, which cannot read zip, so
# unpack zips with PowerShell's Expand-Archive (always present on Windows).
# GNU tar auto-detects gzip for the .tar.gz archives on Linux/macOS.
case "$archive_ext" in
  zip)
    powershell -NoProfile -NonInteractive -Command \
      "Expand-Archive -LiteralPath '$archive' -DestinationPath . -Force" ;;
  *)
    tar -xf "$archive" ;;
esac
chmod +x "$binname" 2>/dev/null || true
bin="$workdir/$binname"

echo "$workdir" >> "$GITHUB_PATH"
echo "bin=$bin" >> "$GITHUB_OUTPUT"
echo "version=$tag" >> "$GITHUB_OUTPUT"
echo "Installed cccc $tag ($target) -> $bin"
