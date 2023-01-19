#!/bin/bash
# installs k3s locally:
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.24.9+k3s2" sh -s - server --cluster-init --write-kubeconfig-mode=644 --kube-apiserver-arg="enable-admission-plugins=NodeRestriction,PodSecurityPolicy"
