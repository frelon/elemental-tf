#!/bin/bash
#
VM_NAME=${1:-elemental-0}
ISO_PATH=${2:-./elemental-teal.arm64.iso}

echo Deploying ${VM_NAME} using ${ISO_PATH}

virt-install --name $VM_NAME --vcpus=4  --memory 3072 \
  --os-variant=sle15sp3 \
  --virt-type qemu \
  --disk path=/var/lib/libvirt/images/${VM_NAME}.img,bus=scsi,size=35,format=qcow2 \
  --check disk_size=off \
  --graphics none \
  --serial pty \
  --console pty,target_type=virtio \
  --rng random \
  --cdrom $ISO_PATH  \
  --autostart \
  --network bridge=vbr0 \
  --arch=aarch64
