# Vagrant Box with Debian and Docker preinstalled

A Debian image based on Bento boxes with Docker and other tools preinstalled

[![License](https://img.shields.io/github/license/D3strukt0r/vagrant-debian-docker?label=License)](LICENSE.txt)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.0-4baaaa)][code-of-conduct]

## Getting Started

### Prerequisites

* [Vagrant](https://developer.hashicorp.com/vagrant/docs/installation) - To run images

#### Quick Guide on macOS

```shell
brew install vagrant
```

### Usage

The box ships with Docker, Buildx and Compose preinstalled, a custom shell
prompt, SSH password auth, GitHub host keys, and an **embedded Vagrantfile** that
configures the machine, network, synced folders, SSH and more for you. That means
your project's `Vagrantfile` only needs:

```ruby
Vagrant.configure('2') do |config|
  config.vm.box = 'D3strukt0r/debian-docker'
end
```

Everything else is driven by a `.vagrant.config.yml` next to your `Vagrantfile`.
Copy [`.vagrant.config.dist.yml`](src/.vagrant.config.dist.yml) and adjust it:

```yaml
vm:
  name: 'My Project'
  cpus: 4
  memory: 4096

network:
  ip: 192.168.56.5
  hostname: 'my-project.test'

folder:
  type: 'nfs' # or "rsync", "smb", or omit for the default shared folder

ssh:
  forward_agent: true

# Optional: start/stop Compose with the machine, log in to a registry, and run
# project-specific scripts. See the dist file for all keys.
docker:
  compose_file: 'compose.vm.yml'
provision:
  post_setup: 'vagrant/post-setup.sh'
  post_boot:  'vagrant/post-boot.sh'
```

Anything you set in your own `Vagrantfile` overrides the box's defaults, and
named provisioners can be overridden individually. For a working example, see
[test/Vagrantfile](test/Vagrantfile) and [test/.vagrant.config.yml](test/.vagrant.config.yml).

## Development

Want to build, test, or publish the box itself? Read on.

### Prerequisites

* [VirtualBox](https://www.virtualbox.org/) - The hypervisor the box is built for
* [Packer](https://developer.hashicorp.com/packer/downloads) - To build images
* [Vagrant](https://developer.hashicorp.com/vagrant/docs/installation) - To run/publish images

On macOS:

```shell
brew tap hashicorp/tap
brew install hashicorp/tap/packer vagrant
brew install --cask virtualbox
```

> **Why is the build local?** GitHub-hosted runners cannot run x86 VirtualBox
> (no nested virtualization on Linux/Windows runners; macOS runners are now
> Apple Silicon). The build therefore runs on your machine; CI only lints and
> validates the sources (`packer fmt`/`validate`, `shellcheck`).

### How it works

* `src/provision.sh` bakes the generic setup into the image at build time
  (Docker + Buildx + Compose, git, custom prompt, SSH password auth, GitHub host
  keys, ...).
* `src/Vagrantfile` is the **shared, embedded Vagrantfile**. `bin/build.sh`
  packages it into the box so consuming projects inherit all the
  network/folder/SSH/trigger config and only need the 3-line `Vagrantfile` above
  plus a `.vagrant.config.yml` (template: `src/.vagrant.config.dist.yml`).
* `src/debian-docker.pkr.hcl` builds on `bento/debian-13`. If the Bento Trixie
  box is not available yet, change `box_basename` to `bento/debian-12`.
* `bin/build.sh` runs the build under an isolated `VAGRANT_HOME`
  (`~/.vagrant.d-build`) so none of your global Vagrant plugins load while
  Packer boots its build VM. This keeps builds reproducible and avoids two
  common breakages: `vagrant-vbguest` rebuilding Guest Additions (fails when the
  box's kernel headers have rotated out of the apt pool) and an outdated
  `vagrant-notify-forwarder` crashing on Ruby >= 3.2.

### Build

```shell
./bin/build.sh
```

This runs `packer init`/`validate`/`build` and embeds `src/Vagrantfile` into the
resulting `build/package.box`. On Windows, run it from Git Bash.

### Test

```shell
cd test
vagrant box add --force debian-docker-local ../build/package.box
vagrant up
vagrant ssh
```

Confirm the box is driving everything from `test/.vagrant.config.yml` (VM name,
CPUs/memory, hostname, IP), the 📦 prompt appears, you land in `/vagrant`,
`docker run hello-world` works, and `git -C /vagrant status` shows no
"dubious ownership" error.

### Lint

The CI workflow (`.github/workflows/ci-cd.yml`) only lints/validates the sources;
no secrets are required. Run the same checks locally:

```shell
packer fmt -check -recursive src/
packer validate src/
shellcheck bin/*.sh src/*.sh
```

### Publish

Boxes are published to the [HCP Vagrant Registry](https://portal.cloud.hashicorp.com/)
(formerly Vagrant Cloud) as `D3strukt0r/debian-docker`.

Create an access token in the HCP Vagrant Registry, then:

```shell
export VAGRANT_CLOUD_TOKEN=<my_access_token>
./bin/publish.sh 1.0.0
```

`bin/publish.sh` wraps `vagrant cloud publish` (create version + provider, upload
and release in one step). If you omit the version argument it uses the exact git
tag of the current commit. Override the defaults via `VAGRANT_CLOUD_BOX`,
`VAGRANT_CLOUD_PROVIDER` or `VAGRANT_CLOUD_FILE` if needed.

Verify the published box from a scratch directory:

```shell
vagrant init D3strukt0r/debian-docker
vagrant up
```

## Contributing

Please read [CONTRIBUTING.md][contributing] for details on our code of conduct and the process for submitting pull requests.

This project uses [Conventional Commits](https://www.conventionalcommits.org/).

## Versioning

We use [SemVer](http://semver.org/) for versioning. For available versions, see the [tags on this repository][gh-tags].

## Authors

### Special thanks for all the people who had helped this project so far

- **Manuele** - [D3strukt0r](https://github.com/D3strukt0r)

See also the full list of [contributors][gh-contributors] who participated in this project.

### I would like to join this list. How can I help the project?

We're currently looking for contributions for the following:

- [ ] Bug fixes
- [ ] Translations
- [ ] etc...

For more information, please refer to our [CONTRIBUTING.md][contributing] guide.

## License

This project is licensed under the MIT License - see the [LICENSE.txt](LICENSE.txt) file for details.

## Acknowledgments

This project uses code from the following libraries:

* [Packer](https://example.com), MIT License

[gh-tags]: https://github.com/D3strukt0r/vagrant-debian-docker/tags
[gh-contributors]: https://github.com/D3strukt0r/vagrant-debian-docker/contributors
[contributing]: https://github.com/D3strukt0r/.github/blob/master/CONTRIBUTING.md
[code-of-conduct]: https://github.com/D3strukt0r/.github/blob/master/CODE_OF_CONDUCT.md
