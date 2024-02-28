#!/bin/bash
# installs k3s locally:
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.10+k3s2" sh -s - server --cluster-init --write-kubeconfig-mode=644
