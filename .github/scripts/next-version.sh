#!/usr/bin/env bash
#
# Computes the next semantic version from Conventional Commits.
#
# Reads the commit range "<latest semver tag>..HEAD" and decides the bump:
#
#   major  - any commit with a `!` before the colon (e.g. `feat!:`, `fix(api)!:`)
#            or a `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer in the body
#   minor  - any `feat:` / `feat(scope):` subject
#   patch  - everything else
#
# Emits `version` and `previous-tag` to $GITHUB_OUTPUT when running under
# GitHub Actions, and always logs the reasoning to stderr/stdout.
#
# Requires the repository to be checked out with `fetch-depth: 0` so that tags
# and full history are present.

set -euo pipefail

# Highest semver tag reachable from HEAD.
#
# Deliberately NOT `git describe --tags --abbrev=0`: that returns the *nearest*
# tag by commit distance, which with merge commits in the history can resolve to
# an older tag than the newest release and recompute a version that already
# exists. Sorting by `-v:refname` picks the highest version instead, and
# `--merged HEAD` keeps tags from unrelated branches out.
LATEST_TAG="$(git tag --list --merged HEAD --sort=-v:refname \
  | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
  | head -n 1 || true)"

if [ -z "${LATEST_TAG}" ]; then
  echo "No semver tag found; treating history as unreleased from 0.0.0"
  MAJOR=0
  MINOR=0
  PATCH=0
  RANGE="HEAD"
else
  echo "Latest tag: ${LATEST_TAG}"
  IFS='.' read -r MAJOR MINOR PATCH <<<"${LATEST_TAG#v}"
  RANGE="${LATEST_TAG}..HEAD"
fi

COMMIT_COUNT="$(git rev-list --count "${RANGE}")"
echo "Commits since ${LATEST_TAG:-<start of history>}: ${COMMIT_COUNT}"

# Conventional Commits puts the type on the subject line and the BREAKING CHANGE
# footer in the body, so the two are matched separately rather than against a
# flattened `%s%n%b` blob.
SUBJECTS="$(git log --format='%s' "${RANGE}")"
BODIES="$(git log --format='%b' "${RANGE}")"

BUMP="patch"

if echo "${SUBJECTS}" | grep -qE '^[a-zA-Z]+(\([^)]*\))?!:' \
  || echo "${BODIES}" | grep -qE '^BREAKING[ -]CHANGE:'; then
  BUMP="major"
elif echo "${SUBJECTS}" | grep -qE '^feat(\([^)]*\))?:'; then
  BUMP="minor"
fi

# A 0.x line is still pre-1.0: a breaking change bumps the minor rather than
# promoting the package to 1.0.0, which is a release decision, not a CI one.
if [ "${BUMP}" = "major" ] && [ "${MAJOR}" -eq 0 ]; then
  echo "Breaking change on a 0.x line: bumping minor instead of promoting to 1.0.0"
  BUMP="minor"
fi

case "${BUMP}" in
  major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
  minor) NEW_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
  patch) NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
esac

echo "Bump type: ${BUMP}"
echo "New version: ${NEW_VERSION}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${NEW_VERSION}"
    echo "previous-tag=${LATEST_TAG}"
    echo "bump=${BUMP}"
  } >>"${GITHUB_OUTPUT}"
fi
