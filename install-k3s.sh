#!/bin/bash
# installs k3s locally:
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.25.8+k3s1" sh -s - server --cluster-init --write-kubeconfig-mode=644
