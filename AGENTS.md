# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, etc.) when working
with code in this repository.

## What this repo is

`vagrant-debian-docker` builds and publishes a custom **VirtualBox Vagrant box**
— Debian 13 (Trixie) with Docker, Buildx and Compose preinstalled — to the HCP
Vagrant Registry as **`D3strukt0r/debian-docker`** (capital `D`; box tags are
case-sensitive). Its purpose is to remove the large, duplicated `Vagrantfile`
boilerplate from the author's other projects: a consuming project collapses to
~3 lines plus a `.vagrant.config.yml`.

## The dedup model (the core idea — read `src/provision.sh` + `src/Vagrantfile` together)

Two layers move generic config out of every consumer:

1. **Baked into the image at build time** — `src/provision.sh` runs as root via
   Packer: installs Docker CE + Buildx + Compose, git with system-wide
   `safe.directory /vagrant`, SSH password auth (an `sshd_config.d` drop-in),
   GitHub host keys in `/etc/ssh/ssh_known_hosts`, the 📦 prompt + auto-`cd
   /vagrant` (`/etc/profile.d` drop-ins), and a bootstrapped buildx builder.
   Docker steps run as the `vagrant` user via `su - vagrant -c` so the
   just-added `docker` group is active in that session. It also applies userspace
   security updates (`apt-get upgrade`, with the kernel held — see gotchas).

2. **Shipped as an embedded Vagrantfile** — `src/Vagrantfile` is packaged
   *inside* the `.box`. Vagrant loads box Vagrantfiles at lowest precedence
   (box < `~/.vagrant.d` < project) and merges them, so a consuming project only
   needs `config.vm.box = 'D3strukt0r/debian-docker'` plus a
   `.vagrant.config.yml`. The embedded file reads that YAML and drives the
   provider / network / synced-folder / SSH-key / docker-login / Compose-trigger
   / project-hook config. The consumer template is `src/.vagrant.config.dist.yml`.

   **Critical:** the embedded Vagrantfile resolves the project directory via
   `ENV['VAGRANT_CWD'] || Dir.pwd` — never `__dir__`, which points into
   `~/.vagrant.d/boxes/...`. It must also degrade gracefully (DHCP / defaults)
   when no config file is present, since the box is shared across projects.

## Commands

Builds are **local-only**: GitHub-hosted runners can't run x86 VirtualBox (no
nested virtualization), so CI only lints/validates. Building needs VirtualBox +
Packer + Vagrant on the host. On Windows, run the scripts from **Git Bash**
(not WSL — they drive the Windows VirtualBox/Packer/Vagrant).

- **Build:** `./bin/build.sh` — `packer init/validate/build` on `bento/debian-13`,
  then injects `src/Vagrantfile` into `build/package.box`.
- **Test:** `cd test && vagrant box add --force debian-docker-local ../build/package.box && vagrant up && vagrant ssh`
- **Lint (same as CI):** `packer fmt -check -recursive src/` · `packer validate src/` ·
  `shellcheck bin/*.sh src/*.sh .github/scripts/*.sh` · `bundle exec rubocop`
  (RuboCop lints the Vagrantfiles; needs Ruby + the tooling Gemfile).
- **Publish:** `./bin/publish.sh <version>` — version defaults to the current git
  tag. Wraps `vagrant cloud publish`. **Auth (HCP Vagrant Registry):** the box's
  org is migrated to HCP, so the old username/password `vagrant cloud auth login`
  is dead (returns `405`). Create an **HCP service principal** at
  https://portal.cloud.hashicorp.com/ (Access control (IAM) > Service principals),
  then `export HCP_CLIENT_ID=… HCP_CLIENT_SECRET=…` (Vagrant ≥ 2.4.3 mints access
  tokens from these automatically). `publish.sh` also accepts an explicit
  `VAGRANT_CLOUD_TOKEN` (wins; for CI) or a token stored via
  `vagrant cloud auth login --token <token>`.
- **Multi-arch:** build + publish the *same* version on each native host (amd64
  on an x86-64 machine, arm64 on an Apple-Silicon Mac — VirtualBox can't emulate
  a foreign CPU). `publish.sh` auto-detects the arch and marks `amd64` as the
  provider default; override via `VAGRANT_CLOUD_ARCH`,
  `VAGRANT_CLOUD_DEFAULT_ARCH`, `VAGRANT_CLOUD_RELEASE`.

## Build internals & gotchas

- **Hermetic build (load-bearing):** `bin/build.sh` runs Packer under an isolated
  `VAGRANT_HOME` (`~/.vagrant.d-build`) so the host's *global* Vagrant plugins
  never load during the build. Without this, `vagrant-vbguest` tries to rebuild
  Guest Additions and fails on rotated kernel headers, and a stale
  `vagrant-notify-forwarder` crashes `vagrant up` on Ruby ≥ 3.2.
- **A `.box` is a gzipped tar.** `build.sh` embeds the Vagrantfile by unpacking
  the box and **appending** to the auto-generated Vagrantfile (which carries the
  NAT `base_mac`) rather than overwriting it, then repacking.
- **Packer script path** uses `${path.root}/provision.sh` so `packer validate
  src/` (and CI) work from the repo root — script paths otherwise resolve
  relative to the current working directory, not the template.
- **Debian 13 fallback:** if Bento hasn't published the Trixie VirtualBox box,
  change `box_basename` in `src/debian-docker.pkr.hcl` to `bento/debian-12`.
- **Guest Additions / kernel are frozen on purpose.** The box keeps the base box's
  GA with `config.vbguest.auto_update = false`, and `provision.sh` patches userspace
  via `apt-get upgrade` while **holding the kernel** — a kernel bump would orphan
  GA's per-kernel `vboxsf` module, and vbguest can't rebuild it (it's broken on Ruby
  ≥ 3.2 like notify-forwarder). The upgrade preseeds
  `grub-pc/install_devices=/dev/sda` so grub's update runs unattended (the old
  "dist-upgrade locks" issue).

## Broken host Vagrant plugins (Ruby 3.3 / Windows)

Three globally-installed Vagrant plugins are broken under Vagrant 2.4's bundled
Ruby 3.3 (one is Windows-specific). The box doesn't depend on any of them — each is
guarded by `Vagrant.has_plugin?` and the hermetic build home keeps them out of the
build — but to use them in everyday Vagrant they must be patched (build a fixed gem
and pin it; see README "pin to a patched fork"):

- **vagrant-notify-forwarder (0.5.0)** — calls `File.exists?` (removed in Ruby 3.2)
  in `action/stop_host_forwarder.rb`, crashing `vagrant up`/`halt`.
  Fix: `File.exists?` → `File.exist?`.
- **vagrant-vbguest (0.32.0)** — same `File.exists?` bug in `hosts/virtualbox.rb`
  (`guess_local_iso`), crashing when it locates the Guest Additions ISO.
  Fix: `File.exists?` → `File.exist?`. (A GA rebuild also needs matching kernel
  headers — see the GA/kernel gotcha above — which is why the box holds the kernel.)
- **vagrant-hostsupdater (1.2.4)** — Windows write path is racy/broken: when elevated
  it writes a temp `.cmd` and runs it via `ShellExecute(… 'runas' …)` (async, hidden)
  then **immediately deletes the temp file**, so the append usually never runs; the
  non-elevated path shells out to `sh` (absent on Windows); and entries containing
  `(` `)` break `cmd echo`. No one-line fix — the Windows branch needs a direct file
  write (when elevated) plus shell-escaping. Easiest in practice: edit the hosts file
  by hand, or reach the box by its IP.

## Conventions

- `.editorconfig`: LF, UTF-8, 2-space indent, final newline. `.gitattributes`
  forces `*.sh` to LF (CRLF breaks the `#!/bin/bash` shebang).
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/).
- CI (`.github/workflows/ci.yml`) lints only — packer fmt/validate, ShellCheck, and
  RuboCop (via `ruby/setup-ruby` + the Gemfile) — using a non-failing-checks pattern:
  each check is `continue-on-error` and wrapped in `.github/scripts/summarize-step.sh`
  (streams output to the job summary); a trailing gate re-derives the job's pass/fail.
  `.rubocop.yml` sets `inherit_mode: merge` on `Exclude` so RuboCop keeps its default
  excludes (vendor/, …) — otherwise CI's bundler-cached `vendor/bundle` gets linted.
- `.devcontainer/` + the root `Gemfile` ship RuboCop (`.rubocop.yml`) + ShellCheck
  for editing the Vagrantfiles/scripts in VS Code without installing Ruby on the
  host. The `Gemfile` is lint-tooling only (Ruby LSP runs RuboCop from it) — it
  is not a Ruby project, and box builds still run on the host.
