#!/usr/bin/env bash
# Regression tests for the two guards that keep bad data out of Formula/hellbox.rb.
#
# Covers the classes the security review found:
#   SEC-01 empty/partial SHA256s, missing version
#   SEC-02 hostile release tag / version reaching the Ruby template
#   SEC-03 the validator that gates merging the generated formula
#
# Run from the repo root or from CI: script/test-guards.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "${here}/.." && pwd)
validator="${here}/validate-formula.sh"
checker="${here}/check-release-inputs.sh"
formula="${root}/Formula/hellbox.rb"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

expect() { # name want-exit status-command...
  local name=$1 want=$2 got=0
  shift 2
  "$@" >"${tmp}/out" 2>&1 || got=$?
  if [[ $got -ne $want ]]; then
    echo "FAIL: ${name} (expected exit ${want}, got ${got})"
    sed 's/^/    /' "${tmp}/out"
    failed=$((failed + 1))
  else
    echo "ok: ${name}"
  fi
}

expect_output() { # name want-text command...
  local name=$1 want=$2 got=0
  shift 2
  "$@" >"${tmp}/out" 2>&1 || got=$?
  if [[ $got -ne 0 ]] || ! grep -qxF "$want" "${tmp}/out"; then
    echo "FAIL: ${name} (expected output '${want}')"
    sed 's/^/    /' "${tmp}/out"
    failed=$((failed + 1))
  else
    echo "ok: ${name}"
  fi
}

fixture() { # name sed-expression
  sed "$2" "$formula" >"${tmp}/$1.rb"
  echo "${tmp}/$1.rb"
}

# The fixtures mutate the live formula, so read the values they substitute
# from it rather than pinning a release: a formula bump must not turn the
# negative tests into no-ops that then fail.
cur_version=$(sed -n 's/^[[:space:]]*version "\(.*\)"$/\1/p' "$formula" | head -n 1)
first_sha=$(sed -n 's/^[[:space:]]*sha256 "\([0-9a-f]*\)"$/\1/p' "$formula" | head -n 1)
last_sha=$(sed -n 's/^[[:space:]]*sha256 "\([0-9a-f]*\)"$/\1/p' "$formula" | tail -n 1)
if [[ -z $cur_version || -z $first_sha || -z $last_sha ]]; then
  echo "FAIL: could not read version and sha256 pins from ${formula}"
  exit 1
fi
# A dot in the version is a sed metacharacter; escape it for the patterns.
ver_re=${cur_version//./\\.}

echo "== release tag / sha256 guard"
expect_output "current tag is accepted" "1.0.27" "$checker" tag "v1.0.27"
expect_output "pre-release tag is accepted" "1.0.0-rc.1" "$checker" tag "v1.0.0-rc.1"
# Backticks are the hostile payload, not a command substitution to expand.
# shellcheck disable=SC2016
expect "tag with ruby interpolation is rejected" 1 "$checker" tag 'v1.0.0#{`id`}'
expect "tag breaking out of a ruby string is rejected" 1 "$checker" tag 'v1.0.0";system("id")'
expect "tag with a path component is rejected" 1 "$checker" tag "v1.0.0/a"
expect "empty tag is rejected" 1 "$checker" tag ""
expect "two-component tag is rejected" 1 "$checker" tag "v1.0"

expect "four full sha256s are accepted" 0 "$checker" sha256 \
  "aa46c31b9f731fe1b92ee7c4988d1d4f291a0f5b6b4134bf9a8f868f15e94e3e" \
  "35ff4575a51f8fe5543f0422fadf8d10622ff96efb2442c229e03ed5ab8db6d6" \
  "3feaa407a72939956cb531fb5de8718c5fb086020f316dc5898cb5cb6e1ec18e" \
  "c62c3a70d61d7bb5aec2e9600f54a0dcb0faa36f48f2ad0fae4ac77589747eb8"
expect "empty sha256 is rejected" 1 "$checker" sha256 "" \
  "35ff4575a51f8fe5543f0422fadf8d10622ff96efb2442c229e03ed5ab8db6d6"
expect "truncated sha256 is rejected" 1 "$checker" sha256 \
  "aa46c31b9f731fe1b92ee7c4988d1d4f291a0f5b6b4134bf9a8f868f15e94e"
expect "uppercase sha256 is rejected" 1 "$checker" sha256 \
  "AA46C31B9F731FE1B92EE7C4988D1D4F291A0F5B6B4134BF9A8F868F15E94E3E"

echo "== generated formula validator"
expect "committed formula passes" 0 "$validator" "$formula"

expect "empty sha256 is rejected" 1 "$validator" \
  "$(fixture empty-hash "s|sha256 \"${first_sha}\"|sha256 \"\"|")"

expect ":no_check is rejected" 1 "$validator" \
  "$(fixture no-check "s|sha256 \"${first_sha}\"|sha256 :no_check|")"

expect "missing fourth sha256 is rejected" 1 "$validator" \
  "$(fixture three-of-four "/sha256 \"${last_sha}\"/d")"

expect "version/url mismatch is rejected" 1 "$validator" \
  "$(fixture version-mismatch "s|version \"${ver_re}\"|version \"${cur_version}.1\"|")"

expect "url from another release is rejected" 1 "$validator" \
  "$(fixture url-mismatch "s|download/v${ver_re}/hellbox-macos-arm64|download/v0.0.0/hellbox-macos-arm64|")"

# shellcheck disable=SC2016
expect "injected ruby interpolation is rejected" 1 "$validator" \
  "$(fixture injected-version "s|version \"${ver_re}\"|version \"${cur_version}#{\`id\`}\"|")"

expect "broken ruby is rejected" 1 "$validator" \
  "$(fixture broken-ruby 's|class Hellbox < Formula|class Hellbox < Formula do|')"

if [[ $failed -ne 0 ]]; then
  echo "${failed} guard test(s) FAILED"
  exit 1
fi
echo "all guard tests passed"
