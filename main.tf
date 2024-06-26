terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "bridge_name" {
  type = string
  default = "vbr0"
}

variable "manager_address" {
  type = string
  default = "10.0.40.60"
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
    elemental_res_b64        = base64encode(file("${path.module}/cluster.yaml"))
    hardening_b64            = base64encode(file("${path.module}/hardening.yaml"))
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

resource "libvirt_volume" "leap" {
  name   = "leap"
  pool   = libvirt_pool.elemental.name
  source = "https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-Cloud.qcow2"
  format = "qcow2"
}

resource "libvirt_volume" "manager" {
  name           = "manager"
  base_volume_id = libvirt_volume.leap.id
  pool           = libvirt_pool.elemental.name
  size           = 50000000000
}

resource "libvirt_domain" "manager" {
  name       = "manager"
  memory     = "6442"
  vcpu       = 8
  autostart  = true
  cloudinit  = libvirt_cloudinit_disk.manager_init.id

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.manager.id
  }

  network_interface {
    bridge         = var.bridge_name
    mac            = "02:52:54:00:5E:01"
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
    # host        = libvirt_domain.manager.network_interface.0.addresses.0
    host        = var.manager_address
    private_key = tls_private_key.manager_private_key.private_key_pem
    timeout     = "5m"
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

resource "null_resource" "kubeconfig" {
  depends_on = [
    libvirt_domain.manager
  ]

  provisioner "local-exec" {
    command = "./kubeconfig.sh"
    working_dir = "${abspath(path.module)}"
  }
}

resource "null_resource" "install_rancher" {
  depends_on = [
    null_resource.kubeconfig
  ]

  provisioner "local-exec" {
    command = "./install-rancher.sh"
    working_dir = "${abspath(path.module)}"
    environment = {
	KUBECONFIG = "./k3s.yaml"
    }
  }
}

resource "null_resource" "install_elemental" {
  depends_on = [
    null_resource.install_rancher
  ]

  provisioner "local-exec" {
    command = "./elemental.sh install"
    working_dir = "${abspath(path.module)}"
    environment = {
	KUBECONFIG = "./k3s.yaml"
    }
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
    null_resource.install_elemental
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

