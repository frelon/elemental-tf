# Elemental terraform files

Terraform files to deploy the elemental stack (including rancher manager) to a
libvirt host.

Requires kubectl, helm and cmctl installed on the host system.

```sh
sudo ./add_br.sh
terraform apply -auto-approve
```
