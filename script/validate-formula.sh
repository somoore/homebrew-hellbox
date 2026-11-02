#!/usr/bin/env bash
# Validate the machine-written Homebrew formula before it can be merged.
#
# The updater workflow writes Formula/hellbox.rb unattended, so this script is
# the gate that keeps a broken or misleading formula off main:
#   * the file must be valid Ruby (it is evaluated by `brew info`/`brew install`)
#   * exactly four sha256 pins, each a full lowercase SHA-256, never :no_check
#   * exactly one `version`, matching every release `url`
#
# Usage: validate-formula.sh [Formula/hellbox.rb]
set -euo pipefail

formula=${1:-Formula/hellbox.rb}
fail=0

err() {
  echo "::error file=${formula}::$*" >&2
  fail=1
}

[[ -f $formula ]] || { echo "::error::formula not found: ${formula}" >&2; exit 1; }

# 1. Syntax. A generated file with a broken string or an injected interpolation
#    fails here rather than at `brew install` time on a user's machine.
if ! ruby -c "$formula" >/dev/null; then
  err "ruby -c failed"
fi

# 2. Checksums: four present, all well formed, none disabled.
sha_lines=$(grep -cE '^[[:space:]]*sha256 "' "$formula" || true)
[[ $sha_lines -eq 4 ]] || err "expected 4 sha256 \"...\" lines, found ${sha_lines}"

while IFS= read -r line; do
  case $line in
    *'sha256 "'*) ;;
    *) continue ;;
  esac
  if ! printf '%s\n' "$line" | grep -qE '^[[:space:]]*sha256 "[0-9a-f]{64}"$'; then
    err "sha256 must be exactly 64 lowercase hex characters: ${line}"
  fi
done < "$formula"

if grep -qE '^[[:space:]]*sha256[[:space:]]+:no_check' "$formula"; then
  err ":no_check disables checksum verification"
fi

# 3. Version/url consistency. Every download URL must be for the pinned version,
#    so a formula can never mix a new version with old (or missing) assets.
versions=$(sed -n 's/^[[:space:]]*version "\(.*\)"$/\1/p' "$formula")
version_count=$(printf '%s' "$versions" | grep -c . || true)
[[ $version_count -eq 1 ]] || err "expected exactly one version line, found ${version_count}"
version=$(printf '%s\n' "$versions" | head -n 1)

if [[ -n $version ]]; then
  if ! printf '%s\n' "$version" | grep -qE '^[0-9]+(\.[0-9]+){2}([-+.][0-9A-Za-z.]+)?$'; then
    err "version is not a plain release version: '${version}'"
  fi

  url_count=$(grep -cE '^[[:space:]]*url "' "$formula" || true)
  [[ $url_count -eq 4 ]] || err "expected 4 url lines, found ${url_count}"

  while IFS= read -r url; do
    case $url in
      "https://github.com/somoore/hellbox/releases/download/v${version}/"*) ;;
      *) err "url does not point at release v${version}: ${url}" ;;
    esac
  done < <(sed -n 's/^[[:space:]]*url "\(.*\)"$/\1/p' "$formula")
fi

if [[ $fail -ne 0 ]]; then
  echo "formula validation FAILED: ${formula}" >&2
  exit 1
fi

echo "formula OK: valid Ruby, 4 sha256 pins, version ${version} matches every url"
