#!/bin/bash
set -e -u -o pipefail
IFS=$'\n\t'
set -x

# Run a command as the unprivileged "vagrant" user in a *fresh* login shell so
# that freshly-added group memberships (e.g. "docker") are already in effect.
runAsUser() {
  su - vagrant -c "$1"
}

# Retry a command a few times -- image pulls from Docker Hub can flake mid-download
# (broken pipe / EOF), which would otherwise abort the whole build.
retry() {
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$attempt" -ge 3 ]; then
      return 1
    fi
    echo "Step failed (attempt $attempt) -- retrying in 5s..."
    attempt=$((attempt + 1))
    sleep 5
  done
}

# ------------------------------------------------------------------------------
# Prepare apt for non-interactive provisioning
# ------------------------------------------------------------------------------
# Fixes "dpkg-reconfigure: unable to re-open stdin: No file or directory" by
# disabling the interactive apt pre-configuration hook.
# See https://serverfault.com/a/717770
if [ -f /etc/apt/apt.conf.d/70debconf ]; then
  sed -i 's@DPkg::Pre-Install-Pkgs@//DPkg::Pre-Install-Pkgs@' /etc/apt/apt.conf.d/70debconf
fi
export DEBIAN_FRONTEND=noninteractive
dpkg-reconfigure debconf -f noninteractive -p critical

apt-get update

# Apply security/userspace updates. Use `upgrade` (NOT dist-upgrade): it holds the
# kernel back, so the box keeps the kernel its Guest Additions module is built for
# (a kernel bump would break vboxsf synced folders, and vbguest can't rebuild it).
# Preseed grub-pc's install device so its update runs unattended -- otherwise the
# grub-pc postinst prompts for the boot disk (the old "dist-upgrade locks" issue).
echo 'grub-pc grub-pc/install_devices multiselect /dev/sda' | debconf-set-selections
NEEDRESTART_MODE=a apt-get -y \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade

apt-get install --no-install-recommends --no-install-suggests --yes \
    ca-certificates curl gnupg lsb-release git

# ------------------------------------------------------------------------------
# Git
# ------------------------------------------------------------------------------
# Every consuming project mounts its code at /vagrant, so mark it safe globally
# to avoid "detected dubious ownership in repository at '/vagrant'".
git config --system --add safe.directory /vagrant

# ------------------------------------------------------------------------------
# Install Docker (+ Buildx & Compose plugins)
# ------------------------------------------------------------------------------
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install --no-install-recommends --no-install-suggests --yes \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Manage Docker as the non-root "vagrant" user
getent group docker >/dev/null || groupadd docker
usermod -aG docker vagrant

# Pre-pull the buildx/buildkit images and create a container-driver builder so
# the first "docker buildx build" in a project is fast. Run as "vagrant" in a
# fresh login shell so the just-added "docker" group is active.
# Note: the binfmt kernel registration itself does not survive a reboot; this
# step primarily pre-pulls the helper images into the box.
retry runAsUser 'docker run --privileged --rm tonistiigi/binfmt --install all'
# Recreate the builder each attempt so a flaked bootstrap (buildkit image pull)
# retries cleanly instead of erroring on the already-existing instance.
retry runAsUser 'docker buildx rm builder-default > /dev/null 2>&1 || true; docker buildx create --name builder-default --driver docker-container --bootstrap --use'

# ------------------------------------------------------------------------------
# SSH
# ------------------------------------------------------------------------------
# Use a drop-in so we stay robust against changes in the base box's sshd_config.
cat > /etc/ssh/sshd_config.d/99-vagrant.conf <<'EOF'
# Allow password auth (handy for quick `vagrant ssh`/scp from the host)
PasswordAuthentication yes
# Speed up SSH connections
UseDNS no
GSSAPIAuthentication no
EOF
service ssh restart

# Trust github.com host keys system-wide so `git clone`/`pull` over SSH works in
# every project without an interactive "unknown host" prompt.
ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts

# ------------------------------------------------------------------------------
# Shell experience for the "vagrant" user (applies to every project)
# ------------------------------------------------------------------------------
# Custom 📦 prompt
cat > /etc/profile.d/10-vagrant-prompt.sh <<'EOF'
export PS1='📦 ${debian_chroot:+($debian_chroot)}\[\e[38;5;46m\]\u@\h\[\e[0m\]:\[\e[38;5;33m\]\w\[\e[0m\]\$ '
EOF

# Drop interactive login shells straight into the synced project folder
cat > /etc/profile.d/20-vagrant-cd.sh <<'EOF'
case $- in
  *i*) [ -d /vagrant ] && cd /vagrant ;;
esac
EOF
