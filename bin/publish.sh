#!/bin/bash
# Publish the built box to the HCP Vagrant Registry (formerly Vagrant Cloud).
#
# Usage:
#   VAGRANT_CLOUD_TOKEN=<token> ./bin/publish.sh [VERSION]
#
# VERSION defaults to the current git tag (e.g. "1.2.3"). Create a token at
# https://portal.cloud.hashicorp.com/ (HCP Vagrant Registry).
set -e -u -o pipefail
IFS=$'\n\t'

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_DIR=$( cd -- "$SCRIPT_DIR/.." &> /dev/null && pwd )

BOX="${VAGRANT_CLOUD_BOX:-D3strukt0r/debian-docker}"
PROVIDER="${VAGRANT_CLOUD_PROVIDER:-virtualbox}"
FILE="${VAGRANT_CLOUD_FILE:-$PROJECT_DIR/build/package.box}"
VERSION="${1:-${VAGRANT_CLOUD_VERSION:-}}"

if [ -z "${VAGRANT_CLOUD_TOKEN:-}" ]; then
  echo "ERROR: VAGRANT_CLOUD_TOKEN is not set." >&2
  echo "       Create one at https://portal.cloud.hashicorp.com/ and export it." >&2
  exit 1
fi

# Fall back to the exact git tag of the current commit (strip a leading "v").
if [ -z "$VERSION" ]; then
  VERSION=$(git -C "$PROJECT_DIR" describe --tags --exact-match 2>/dev/null || true)
  VERSION="${VERSION#v}"
fi
if [ -z "$VERSION" ]; then
  echo "ERROR: no version given. Pass it as the first argument (e.g." >&2
  echo "       ./bin/publish.sh 1.0.0) or tag the current commit." >&2
  exit 1
fi

if [ ! -f "$FILE" ]; then
  echo "ERROR: box file not found at $FILE. Run ./bin/build.sh first." >&2
  exit 1
fi

echo "Publishing $BOX $VERSION ($PROVIDER) from $FILE ..."
vagrant cloud publish \
  --release \
  --force \
  "$BOX" "$VERSION" "$PROVIDER" "$FILE"
