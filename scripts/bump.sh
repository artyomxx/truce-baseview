#!/usr/bin/env bash
# Bump the package version in Cargo.toml and commit. Plain semver on the
# fork's own line (see "Versioning and releases" in README.md):
#
#   scripts/bump.sh patch    0.2.0 -> 0.2.1   a fix, no public API change
#   scripts/bump.sh minor    0.2.1 -> 0.3.0   a breaking API change, an
#                                             upstream rebase that changes
#                                             the API, or a raised MSRV
#   scripts/bump.sh X.Y.Z                     an explicit version
#
# Pre-release versions (the old X.Y.Z-truce.N) are refused: a pre-release
# can't be picked up through a caret requirement, which is the point of
# the scheme.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cd "$(git rev-parse --show-toplevel)"

if [[ $# -ne 1 ]]; then
    echo "Usage: scripts/bump.sh patch | minor | X.Y.Z"
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Working tree dirty. Commit or stash first."
    exit 1
fi

current=$(awk -F\" '/^version = "/ { print $2; exit }' Cargo.toml)
if [[ -z "$current" ]]; then
    echo "Could not parse version from Cargo.toml"
    exit 1
fi

# Strip a pre-release suffix before the arithmetic, so the first bump off
# the old scheme works: 0.1.1-truce.14 + minor = 0.2.0.
base="${current%%-*}"
if ! [[ "$base" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Version '$current' isn't X.Y.Z. Edit Cargo.toml manually."
    exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$1" in
    patch) next="$major.$minor.$((patch + 1))" ;;
    minor) next="$major.$((minor + 1)).0" ;;
    *)
        if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "'$1' isn't patch, minor or a plain X.Y.Z version."
            exit 1
        fi
        next="$1"
        ;;
esac

echo "Bumping version: $current -> $next"

# Only rewrites the column-0 `version = "..."` line (the package version).
# Dependency versions appear as `windows = { version = "..." }` etc. and
# don't start with "version" at column 0, so they're untouched.
awk -v new="$next" '
    /^version = "/ && !done { sub(/"[^"]+"/, "\"" new "\""); done=1 }
    { print }
' Cargo.toml > Cargo.toml.tmp && mv Cargo.toml.tmp Cargo.toml

# Refresh Cargo.lock so the new version lands there too.
"$CARGO" check --offline --quiet 2>/dev/null || "$CARGO" check --quiet

git add Cargo.toml
# Cargo.lock is normally tracked for the fork, but some checkouts gitignore
# it; staging an ignored path errors out, so only add it when git accepts it.
if ! git check-ignore -q Cargo.lock; then
    git add Cargo.lock
fi
git commit -m "Bump version to $next"

echo "Committed. Next: scripts/release.sh"
