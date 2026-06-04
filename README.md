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

Inside your `Vagrantfile` simply use our image as base image:

```vagrantfile
Vagrant.configure('2') do |config|
  config.vm.box = 'd3strukt0r/debian-docker'
end
```

For a complete example that we also use for testing, check out [test/Vagrantfile](test/Vagrantfile)

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
