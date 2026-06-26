#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Applying patches to third-party packages..."

cd "$REPO_ROOT/third_party/FoundationPose"
git apply "$REPO_ROOT/patches/FoundationPose.patch" --ignore-whitespace
echo "  [OK] FoundationPose"

echo "All patches applied."
