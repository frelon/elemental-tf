terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.7.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_network" "nucnet" {
  name = "nucnet"
  mode = "bridge"
  bridge = "vbr0"
}

resource "libvirt_pool" "nuclab" {
  name = "nuclab"
  type = "dir"
  path = "/home/frelon/libvirt_nuclab"
}

resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "commoninit.iso"
  user_data = data.template_file.user_data.rendered
  pool      = libvirt_pool.nuclab.name
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
}

resource "libvirt_volume" "leap" {
  name   = "leap"
  source = "https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.4/images/openSUSE-Leap-15.4.x86_64-NoCloud.qcow2"
  pool   = libvirt_pool.nuclab.name
}

resource "libvirt_volume" "disk_jumper" {
  name           = "disk_jumper"
  base_volume_id = libvirt_volume.leap.id
  pool           = libvirt_pool.nuclab.name
}

resource "libvirt_domain" "jumper" {
  name     = "jumper"
  firmware = "/usr/share/qemu/ovmf-x86_64-code.bin"
  memory   = "1024"
  vcpu     = 2

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  disk {
    volume_id = libvirt_volume.disk_jumper.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}
