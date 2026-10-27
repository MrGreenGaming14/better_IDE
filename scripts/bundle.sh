#!/usr/bin/env bash
# Build the offline portable tarball dist/bide-offline-linux-x86_64.tar.gz
set -euo pipefail

BIDE_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$BIDE_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "bide bundle: commit first so the bundle matches GitHub" >&2
  exit 1
fi

if [[ ! -f vendor/.build-root || ! -x vendor/nvim/bin/nvim ]]; then
  echo "bide bundle: vendor tree missing or incomplete — run scripts/vendor.sh first" >&2
  exit 1
fi

mkdir -p dist
tarball="dist/bide-offline-linux-x86_64.tar.gz"
shafile="$tarball.sha256"

echo "bide bundle: creating $tarball..."
{ git ls-files -z; printf 'vendor\0'; } | tar --null -T - --transform 's,^,bide/,' -czf "$tarball"

sha256sum "$tarball" > "$shafile"

echo "bide bundle: done"
ls -lh "$tarball" "$shafile"
