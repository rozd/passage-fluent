#!/usr/bin/env bash
#
# Writes RELEASE_NOTES.md for the release being cut.
#
# Collects every commit in "<PREVIOUS_TAG>..HEAD" and groups it by Conventional
# Commit type, so the notes line up with the version bump computed by
# next-version.sh from the same range.
#
# Inputs (environment):
#   VERSION       - the version being released, e.g. 0.1.0
#   PREVIOUS_TAG  - the tag the range starts from; empty for a first release
#
# Requires a checkout with `fetch-depth: 0`.

set -euo pipefail

VERSION="${VERSION:?VERSION is required}"
PREVIOUS_TAG="${PREVIOUS_TAG:-}"

if [ -n "${PREVIOUS_TAG}" ] && git rev-parse -q --verify "refs/tags/${PREVIOUS_TAG}" >/dev/null; then
  RANGE="${PREVIOUS_TAG}..HEAD"
else
  RANGE="HEAD"
fi

SUBJECTS="$(git log --no-merges --format='%s' "${RANGE}")"

# Prints a "### <heading>" section for every subject matching <regex>, then
# strips the `type(scope):` prefix so the bullets read as plain descriptions.
section() {
  local heading="$1" regex="$2" matched
  matched="$(echo "${SUBJECTS}" | grep -E "${regex}" || true)"
  if [ -n "${matched}" ]; then
    echo "### ${heading}"
    echo ""
    echo "${matched}" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?!?: */* /'
    echo ""
  fi
}

{
  echo "## What's Changed"
  echo ""

  section "⚠️ Breaking Changes" '^[a-zA-Z]+(\([^)]*\))?!:'
  section "Features"            '^feat(\([^)]*\))?:'
  section "Bug Fixes"           '^fix(\([^)]*\))?:'
  section "Performance"         '^perf(\([^)]*\))?:'
  section "Documentation"       '^docs(\([^)]*\))?:'

  # Anything that is not one of the categories above, including commits that do
  # not follow Conventional Commits at all.
  OTHER="$(echo "${SUBJECTS}" \
    | grep -vE '^[a-zA-Z]+(\([^)]*\))?!:' \
    | grep -vE '^(feat|fix|perf|docs)(\([^)]*\))?:' || true)"
  if [ -n "${OTHER}" ]; then
    echo "### Other Changes"
    echo ""
    echo "${OTHER}" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?: */* /; s/^([^*])/* \1/'
    echo ""
  fi

  REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-rozd/passage-fluent}"
  if [ -n "${PREVIOUS_TAG}" ]; then
    echo "**Full Changelog**: ${REPO_URL}/compare/${PREVIOUS_TAG}...${VERSION}"
  else
    echo "**Full Changelog**: ${REPO_URL}/commits/${VERSION}"
  fi
} >RELEASE_NOTES.md

echo "Generated RELEASE_NOTES.md for ${VERSION} (range: ${RANGE})"
cat RELEASE_NOTES.md
