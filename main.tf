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
  default = 0
}

variable "rancher_domain_name" {
  type = string
  default = "rancher.test.lab"
}

variable "libvirt_pool_path" {
  type = string
  default = "~/libvirt_elemental"
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "tls_private_key" "manager_private_key" {
  algorithm = "ED25519"
}

data "tls_public_key" "manager_public_key" {
  private_key_pem = tls_private_key.manager_private_key.private_key_pem
}

data "template_file" "manager_user" {
  template = file("${path.module}/manager.user")

  vars = {
    install_k3s_b64          = base64encode(file("${path.module}/install-k3s.sh"))
    install_k3s_services_b64 = base64encode(file("${path.module}/install-k3s-services.sh"))
    elemental_res_b64        = base64encode(file("${path.module}/elemental-res.yaml"))
    manager_public_key       = data.tls_public_key.manager_public_key.public_key_openssh
  }
}

data "template_file" "manager_meta" {
  template = file("${path.module}/manager.meta")
}

resource "libvirt_pool" "elemental" {
  name = "elemental"
  type = "dir"
  path = pathexpand("${var.libvirt_pool_path}")
}

resource "libvirt_cloudinit_disk" "manager_init" {
  name      = "cidata-manager.iso"
  pool      = libvirt_pool.elemental.name

  user_data = data.template_file.manager_user.rendered
  meta_data = data.template_file.manager_meta.rendered
}

resource "libvirt_volume" "tumbleweed" {
  name   = "tumbleweed"
  pool   = "elemental"
  source = "https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-1.0.0-Cloud-Snapshot20230116.qcow2"
  format = "qcow2"
}

resource "libvirt_volume" "manager" {
  name           = "manager"
  base_volume_id = libvirt_volume.tumbleweed.id
  pool           = libvirt_pool.elemental.name
  size           = 40000000000
}

resource "libvirt_domain" "manager" {
  name       = "manager"
  memory     = "4096"
  vcpu       = 4
  autostart  = true
  cloudinit  = libvirt_cloudinit_disk.manager_init.id
  qemu_agent = true

  disk {
    volume_id = libvirt_volume.manager.id
  }

  network_interface {
    bridge         = var.bridge_name
    mac            = "02:52:54:00:5E:01"
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

  connection {
    type        = "ssh"
    user        = "rancher"
    host        = libvirt_domain.manager.network_interface.0.addresses.0
    private_key = tls_private_key.manager_private_key.private_key_pem
    timeout     = "30m"
  }

  provisioner "remote-exec" {
    inline = [
        "echo waiting for kubeconfig",
        "while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do sleep 1; done;",
        "echo waiting for k8s api",
        "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; while ! kubectl get nodes; do sleep 1; done;",
    ]
  }
}

output "manager_ip" {
  value = libvirt_domain.manager.network_interface.0.addresses.0
}

resource "null_resource" "install_k3s_services" {
  connection {
    type        = "ssh"
    user        = "rancher"
    host        = libvirt_domain.manager.network_interface.0.addresses.0
    private_key = tls_private_key.manager_private_key.private_key_pem
    timeout     = "30m"
  }

  provisioner "remote-exec" {
    inline = [
        "/var/rancher/install-k3s-services.sh",
    ]
  }
}

resource "null_resource" "elemental_iso" {
  depends_on = [
    null_resource.install_k3s_services
  ]

  provisioner "local-exec" {
    command = "echo 'follow the elemental quickstart to generate an iso'; until [ -f elemental-teal.x86_64.iso ]; do sleep 5; done;"
  }
}

resource "libvirt_volume" "node" {
  name   = "node-${count.index}"
  pool   = libvirt_pool.elemental.name
  format = "qcow2"
  size   = 40000000000

  count = var.num_nodes
}

resource "libvirt_domain" "node" {
  depends_on = [
    null_resource.elemental_iso
  ]

  name = "node-${count.index}"

  memory   = "4096"
  vcpu     = 4
  autostart = true
  qemu_agent = true
  firmware   = "/usr/share/qemu/ovmf-x86_64-suse-code.bin"

  boot_device {
    dev = [ "hd", "cdrom"]
  }

  disk {
    file = abspath("${path.module}/elemental-teal.x86_64.iso")
  }

  disk {
    volume_id = element(libvirt_volume.node.*.id, count.index)
  }

  tpm {
    backend_type    = "emulator"
    backend_version = "2.0"
  }

  network_interface {
    bridge         = var.bridge_name
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

  count = var.num_nodes
}

