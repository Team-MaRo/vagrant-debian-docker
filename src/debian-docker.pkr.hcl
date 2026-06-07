variable "box_basename" {
  type    = string
  default = "bento/debian-13"
}

variable "build_directory" {
  type    = string
  default = "../build"
}

packer {
  required_plugins {
    vagrant = {
      version = ">= 1.0.2"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

source "vagrant" "base" {
  communicator = "ssh"
  source_path  = var.box_basename
  provider     = "virtualbox"
  add_force    = true
  output_dir   = var.build_directory
}

build {
  name    = "debian-docker"
  sources = ["source.vagrant.base"]

  # Provision as root (Docker, apt, SSH, system-wide shell config). The script
  # itself drops to the "vagrant" user where appropriate.
  provisioner "shell" {
    environment_vars = ["HOME_DIR=/home/vagrant"]
    execute_command  = "echo 'vagrant' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    script           = "${path.root}/provision.sh"
  }

  # The shared box Vagrantfile (src/Vagrantfile) is embedded into the resulting
  # box by bin/build.sh after Packer finishes. See README.md ("Development").
}
