#!/bin/bash
# Build the VirtualBox box with Packer and embed the shared Vagrantfile.
#
# Requires VirtualBox + Packer on the host (builds cannot run on GitHub-hosted
# runners, which lack x86 nested virtualization). Runs on Linux/macOS and on
# Windows via Git Bash or WSL.
set -e -u -o pipefail
IFS=$'\n\t'

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_DIR=$( cd -- "$SCRIPT_DIR/.." &> /dev/null && pwd )

SRC_DIR="$PROJECT_DIR/src"
BUILD_DIR="$PROJECT_DIR/build"
BOX_FILE="$BUILD_DIR/package.box"

# ------------------------------------------------------------------------------
# Build in an isolated VAGRANT_HOME (hermetic build)
# ------------------------------------------------------------------------------
# Packer's vagrant builder runs `vagrant up` under the hood, which loads every
# Vagrant plugin installed on the host -- and some break the build:
#   * vagrant-vbguest rebuilds Guest Additions and fails when the box's pinned
#     kernel headers have rotated out of Debian's apt pool.
#   * an outdated vagrant-notify-forwarder calls File.exists?, removed in Ruby
#     >= 3.2 (Vagrant 2.4 bundles Ruby 3.3), and crashes `vagrant up`.
# Pointing VAGRANT_HOME at a dedicated, plugin-free directory keeps the build
# reproducible regardless of what's installed globally. The base box is cached
# there, so only the first build downloads it.
BUILD_HOME="${VDD_VAGRANT_HOME:-$HOME/.vagrant.d-build}"
mkdir -p "$BUILD_HOME"
if command -v cygpath > /dev/null 2>&1; then
  # On Git Bash (Windows), vagrant.exe needs a native Windows path.
  VAGRANT_HOME="$(cygpath -w "$BUILD_HOME")"
else
  VAGRANT_HOME="$BUILD_HOME"
fi
export VAGRANT_HOME
echo "Using isolated VAGRANT_HOME=$VAGRANT_HOME"

# ------------------------------------------------------------------------------
# Build
# ------------------------------------------------------------------------------
cd "$SRC_DIR"
packer init .
packer validate .
packer build -force debian-docker.pkr.hcl

if [ ! -f "$BOX_FILE" ]; then
  echo "ERROR: expected box not found at $BOX_FILE" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Embed the shared Vagrantfile
# ------------------------------------------------------------------------------
# A .box is a gzipped tarball (metadata.json, box.ovf, *.vmdk, [Vagrantfile]).
# We add our Vagrantfile so consuming projects inherit the shared config. If the
# base box already ships a Vagrantfile (e.g. with the NAT base MAC), we append
# to it rather than replacing it -- Vagrant merges multiple configure blocks.
echo "Embedding $SRC_DIR/Vagrantfile into $BOX_FILE ..."
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

tar -xzf "$BOX_FILE" -C "$workdir"

if [ -f "$workdir/Vagrantfile" ]; then
  printf '\n' >> "$workdir/Vagrantfile"
  cat "$SRC_DIR/Vagrantfile" >> "$workdir/Vagrantfile"
else
  cp "$SRC_DIR/Vagrantfile" "$workdir/Vagrantfile"
fi

# Repack from inside the directory so entries have no leading "./".
( cd "$workdir" && tar -czf "$BOX_FILE" -- * )

echo "Built box with embedded Vagrantfile: $BOX_FILE"
tar -tzf "$BOX_FILE" | sed 's/^/  /'
