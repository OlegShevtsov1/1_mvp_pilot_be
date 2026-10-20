#!/usr/bin/env bash
# On the public mirror: checks that a release tag may go to prod there (resolve_mirror_release in
# deploy/_common.sh: the release tag checks on the mirror's tag, and MIRROR_SOURCE.json recording
# source_sha as its primary commit) and prints version=sha-<source_sha>, ready for GITHUB_OUTPUT.
# Usage: deploy/mirror_source_check.sh vX.Y.Z <source_sha>   (in a clone whose origin is the mirror)
# Exit 0: the pair qualifies. 1: it does not (the reason is on stderr). 2: malformed input.
set -euo pipefail

# shellcheck source=deploy/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

[[ $# -eq 2 ]] || { echo "usage: $0 vX.Y.Z <source_sha>" >&2; exit 2; }
version="$(resolve_mirror_release "$1" "$2")"
echo "version=${version}"
