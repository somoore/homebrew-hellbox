#!/usr/bin/env bash
# Validate values that are written verbatim into the generated Formula/hellbox.rb.
#
# The hellbox release tag is untrusted input. Git allows "#", "{", "}", "`",
# '"', ";", "$" and "()" in a ref name, and the formula template interpolates
# the tag and version inside double-quoted Ruby strings. Anything that is not a
# plain release tag is rejected before it can reach the template.
#
# Usage:
#   check-release-inputs.sh tag <TAG>        # prints the version for TAG
#   check-release-inputs.sh sha256 <SHA>...  # succeeds if every SHA is 64 lowercase hex
set -euo pipefail

tag_re='^v?[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.]+)?$'
version_re='^[0-9]+(\.[0-9]+){2}([-+.][0-9A-Za-z.]+)?$'
sha_re='^[0-9a-f]{64}$'

usage() {
  echo "usage: $0 tag <TAG> | sha256 <SHA>..." >&2
  exit 2
}

cmd=${1-}
shift || true

case "$cmd" in
  tag)
    tag=${1-}
    [[ $tag =~ $tag_re ]] || { echo "unexpected release tag: '${tag}'" >&2; exit 1; }
    version=${tag#v}
    [[ $version =~ $version_re ]] || { echo "unexpected version '${version}' for tag '${tag}'" >&2; exit 1; }
    printf '%s\n' "$version"
    ;;
  sha256)
    (($# > 0)) || usage
    for sha in "$@"; do
      [[ $sha =~ $sha_re ]] || { echo "missing or invalid sha256: '${sha}'" >&2; exit 1; }
    done
    ;;
  *)
    usage
    ;;
esac
