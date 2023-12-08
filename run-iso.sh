#!/bin/bash
#
VM_NAME=${1:-elemental-0}
ISO_PATH=${2:-./sle-micro.x86_64.iso}

echo Deploying ${VM_NAME} using ${ISO_PATH}

virt-install --name $VM_NAME --vcpus=4  --memory 3072 --cpu host \
  --os-variant=sle15sp3 \
  --virt-type kvm \
  --boot loader=/usr/share/qemu/ovmf-x86_64-smm-suse-code.bin,loader.readonly=on,loader.secure=on,loader.type=pflash \
  --disk path=/var/lib/libvirt/images/${VM_NAME}.qcow2,bus=scsi,size=30,format=qcow2 \
  --features smm.state=on \
  --check disk_size=off \
  --graphics none \
  --serial pty \
  --console pty,target_type=virtio \
  --rng random \
  --tpm emulator,model=tpm-crb,version=2.0 \
  --cdrom $ISO_PATH  \
  --autostart \
  --network bridge=vbr0
