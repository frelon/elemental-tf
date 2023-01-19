#!/bin/sh
virt-copy-out -a /home/frelon/libvirt_elemental/manager /etc/rancher/k3s/k3s.yaml .
sed -i 's/127\.0\.0\.1/10.0.40.60/' k3s.yaml
chmod 600 k3s.yaml
