# Elemental terraform files

Terraform files to deploy the elemental stack (including rancher manager) to a
libvirt host.

Requires go, kubectl, helm and cmctl installed on the host system.

```sh
sudo ./bridge.sh up
sudo ./bridge.sh iptables
terraform apply -auto-approve
KUBECONFIG=k3s.yaml kubectl apply -f cluster.yaml
KUBECONFIG=k3s.yaml go run ./new-vm.go
```
