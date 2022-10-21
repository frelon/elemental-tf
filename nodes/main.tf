terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.7.0"
    }
  }
}

variable "bridge_name" {
  type = string
  default = "vbr0"
}

variable "num_nodes" {
  type = number
  default = 1
}

variable "rancher_domain_name" {
  type = string
  default = "rancher.ranchernuc.lab"
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_pool" "elemental_nodes" {
  name = "elemental_nodes"
  type = "dir"
  path = "/home/frelon/libvirt_elemental_nodes"
}

resource "libvirt_volume" "node" {
  name   = "node-${count.index}"
  pool   = libvirt_pool.elemental_nodes.name
  format = "qcow2"
  size   = 50000000000 # 50GB

  count = var.num_nodes
}

resource "libvirt_domain" "node" {
  name = "node-${count.index}"

  memory     = "4096"
  vcpu       = 4
  autostart  = true
  qemu_agent = true
  firmware   = "/usr/share/qemu/ovmf-x86_64-suse-code.bin"

  boot_device {
    dev = [ "hd", "cdrom"]
  }

  disk {
    file = "${path.cwd}/elemental-teal.x86_64.iso"
  }

  disk {
    volume_id = element(libvirt_volume.node.*.id, count.index)
  }

  network_interface {
    bridge         = var.bridge_name
    mac            = "02:52:54:00:5E:${format("%02d", count.index+1)}"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_port = "1"
    target_type = "virtio"
  }

  tpm {
    backend_type    = "emulator"
    backend_version = "2.0"
  }

  count = var.num_nodes
}

