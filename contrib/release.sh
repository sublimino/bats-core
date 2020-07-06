#!/usr/bin/env bash
#
# bats-core git releaser
#
## Usage: %SCRIPT_NAME% [options]
##
## Options:
##   --major            Major version bump
##   --minor            Minor version bump
##   --patch            Patch version bump
##
##   -v, --version      Print version
##   --debug            Enable debug mode
##   -h, --help         Display this message
##

set -Eeuo pipefail

DIR=$(cd "$(dirname "${0}")" && pwd)
THIS_SCRIPT="${DIR}/$(basename "${0}")"
BATS_VERSION=$(
  # shellcheck disable=SC1090
  source <(grep '^export BATS_VERSION=' libexec/bats-core/bats)
  echo "${BATS_VERSION}"
)
declare -r DIR
declare -r THIS_SCRIPT
declare -r BATS_VERSION

BUMP_INTERVAL=""
NEW_BATS_VERSION=""

main() {
  handle_arguments "${@}"

  if [[ "${BUMP_INTERVAL:-}" == "" ]]; then
    echo "${BATS_VERSION}"
    exit 0
  fi

  local NEW_BATS_VERSION
  NEW_BATS_VERSION=$(semver bump "${BUMP_INTERVAL}" "${BATS_VERSION}")
  declare -r NEW_BATS_VERSION

  echo "Releasing: ${BATS_VERSION} to ${NEW_BATS_VERSION}"
  echo

  replace_in_files

  write_changelog

  git diff --staged

  cat <<EOF
# To complete the release:

1. Manually edit the CHANGELOG diffs in docs/CHANGELOG.md

2. Commit the changes

git commit -m "feat: release Bats v${NEW_BATS_VERSION}"

3. Generate the changelog, and tag the release
# changelog start
EOF

local DELIM=$(echo -en "\001");
sed -E -n "\\${DELIM}^## \[${NEW_BATS_VERSION}\]${DELIM},\\${DELIM}^## ${DELIM}p" docs/CHANGELOG.md \
  | sed -E \
    -e 's,^## \[([0-9\.]+)] - (.*),Bats \1\n\nReleased: \2,' \
    -e 's,^### (.*),\1:,g' \
  | head -n -2 | tee /tmp/bats-release

  cat <<EOF
# changelog end. Copy the output into the tag notes
git tag -a -s "v${NEW_BATS_VERSION}" --message /tmp/bats-release

4. Push the changes

git push --follow-tags

5. Use Github hub to make a draft release

hub release create "v${NEW_BATS_VERSION}" --draft --file /tmp/bats-release.txt
EOF

  exit 0
}

replace_in_files() {
  declare -a FILE_REPLACEMENTS=(
    ".appveyor.yml,^version:"
    "contrib/rpm/bats.spec,^Version:"
    "libexec/bats-core/bats,^export BATS_VERSION="
    "package.json,^  \"version\":"
  )

  for FILE_REPLACEMENT in "${FILE_REPLACEMENTS[@]}"; do
    FILE="${FILE_REPLACEMENT/,*/}"
    MATCH="${FILE_REPLACEMENT/*,/}"
    sed -E -i.bak "/${MATCH}/ { s,${BATS_VERSION},${NEW_BATS_VERSION},g; }" "${FILE}"
    rm "${FILE}.bak" || true
    git add -f "${FILE}"
  done
}

write_changelog() {
  local FILE="docs/CHANGELOG.md"
  sed -E -i.bak "/## \[Unreleased\]/ a \\\n## [${NEW_BATS_VERSION}] - $(date +%Y-%m-%d)" "${FILE}"

  rm "${FILE}.bak" || true

  cp "${FILE}" "${FILE}.new"
  sed -E -i.bak '/## \[Unreleased\]/,+1d' "${FILE}"
  git add -f "${FILE}"
  mv "${FILE}.new" "${FILE}"
}

handle_arguments() {
  parse_arguments "${@:-}"
}

parse_arguments() {
  local CURRENT_ARG

  if [[ "${#}" == 1 && "${1:-}" == "" ]]; then
    return 0
  fi

  while [[ "${#}" -gt 0 ]]; do
    CURRENT_ARG="${1}"

    case ${CURRENT_ARG} in
    --major)
      BUMP_INTERVAL="major"
      ;;
    # ---
    --minor)
      BUMP_INTERVAL="minor"
      ;;
    --patch)
      BUMP_INTERVAL="patch"
      ;;
    -h | --help) usage ;;
    -v | --version)
      get_version
      exit 0
      ;;
    --debug)
      set -xe
      ;;
    -*) usage "${CURRENT_ARG}: unknown option" ;;
    esac
    shift
  done
}

semver() {
  "${DIR}/semver" "${@:-}"
}

usage() {
  sed -n '/^##/,/^$/s/^## \{0,1\}//p' "${THIS_SCRIPT}" | sed "s/%SCRIPT_NAME%/$(basename "${THIS_SCRIPT}")/g"
  exit 2
} 2>/dev/null

get_version() {
  echo "${THIS_SCRIPT_VERSION:-0.1}"
}

main "${@}"
