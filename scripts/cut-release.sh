#!/usr/bin/env bash
# Usage: scripts/cut-release.sh
# Commit all changes first: git commit -m "..."
set -euo pipefail

DATE=$(date +%Y.%m.%d)
HASH=$(git rev-parse --short HEAD)
TAG="v${DATE}-${HASH}"

echo "→ ${TAG}"
git tag "${TAG}"
git push origin "${TAG}"
