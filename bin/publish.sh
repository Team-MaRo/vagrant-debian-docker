#!/bin/bash
# Publish the built box to the HCP Vagrant Registry (formerly Vagrant Cloud).
#
# Usage:
#   ./bin/publish.sh [VERSION]
#
# Authentication (HCP Vagrant Registry) -- use any one:
#   * HCP_CLIENT_ID + HCP_CLIENT_SECRET from an HCP service principal (Vagrant
#     2.4.3+ mints access tokens from these automatically), or
#   * VAGRANT_CLOUD_TOKEN=<token> for this invocation (takes precedence; CI), or
#   * a token stored once via `vagrant cloud auth login --token <token>`.
# Create a service principal at https://portal.cloud.hashicorp.com/ under
# Access control (IAM) > Service principals. NOTE: the old username/password
# `vagrant cloud auth login` no longer works after the HCP migration (405).
#
# VERSION defaults to the current git tag (e.g. "1.2.3").
#
# Multi-arch: run this on each native host (amd64 PC, arm64 Mac) with the SAME
# version; the box then carries both architectures under one version+provider.
# The architecture defaults to the host's (override with VAGRANT_CLOUD_ARCH);
# VAGRANT_CLOUD_DEFAULT_ARCH (default amd64) marks the provider's default arch.
set -e -u -o pipefail
IFS=$'\n\t'

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_DIR=$( cd -- "$SCRIPT_DIR/.." &> /dev/null && pwd )

BOX="${VAGRANT_CLOUD_BOX:-D3strukt0r/debian-docker}"
PROVIDER="${VAGRANT_CLOUD_PROVIDER:-virtualbox}"
FILE="${VAGRANT_CLOUD_FILE:-$PROJECT_DIR/build/package.box}"
VERSION="${1:-${VAGRANT_CLOUD_VERSION:-}}"

# `vagrant cloud publish` defaults --architecture to the host arch; set it
# explicitly (overridable) and normalise what uname reports.
case "$(uname -m)" in
  x86_64 | amd64) host_arch=amd64 ;;
  arm64 | aarch64) host_arch=arm64 ;;
  *) host_arch="$(uname -m)" ;;
esac
ARCH="${VAGRANT_CLOUD_ARCH:-$host_arch}"
# Which architecture is the provider's *default* (served to hosts without an
# exact match and to older Vagrant). amd64 is the broad, safe choice.
DEFAULT_ARCH="${VAGRANT_CLOUD_DEFAULT_ARCH:-amd64}"
# Release the version after upload (set VAGRANT_CLOUD_RELEASE=0 to stage only).
RELEASE="${VAGRANT_CLOUD_RELEASE:-1}"

# Authentication: accept an HCP service principal (HCP_CLIENT_ID +
# HCP_CLIENT_SECRET), an explicit VAGRANT_CLOUD_TOKEN (wins if set), or a token
# stored by a prior `vagrant cloud auth login --token <token>`.
LOGIN_TOKEN_FILE="${VAGRANT_HOME:-$HOME/.vagrant.d}/data/vagrant_login_token"
have_sp=false
if [ -n "${HCP_CLIENT_ID:-}" ] && [ -n "${HCP_CLIENT_SECRET:-}" ]; then
  have_sp=true
fi
if [ -z "${VAGRANT_CLOUD_TOKEN:-}" ] && [ "$have_sp" = false ] && [ ! -s "$LOGIN_TOKEN_FILE" ]; then
  echo "ERROR: not authenticated to the HCP Vagrant Registry. Use one of:" >&2
  echo "       * export HCP_CLIENT_ID + HCP_CLIENT_SECRET (an HCP service principal" >&2
  echo "         from https://portal.cloud.hashicorp.com/ > IAM > Service principals)" >&2
  echo "       * export VAGRANT_CLOUD_TOKEN=<token>" >&2
  echo "       * run 'vagrant cloud auth login --token <token>' once" >&2
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

if [ "$ARCH" = "$DEFAULT_ARCH" ]; then
  default_flag=--default-architecture
else
  default_flag=--no-default-architecture
fi
if [ "$RELEASE" = "0" ] || [ "$RELEASE" = "false" ]; then
  release_flag=--no-release
else
  release_flag=--release
fi

echo "Publishing $BOX $VERSION ($PROVIDER, $ARCH) from $FILE ..."
vagrant cloud publish \
  "$release_flag" \
  --force \
  --architecture "$ARCH" \
  "$default_flag" \
  "$BOX" "$VERSION" "$PROVIDER" "$FILE"
