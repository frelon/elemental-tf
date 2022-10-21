#!/bin/bash

set -e

function install_cert_manager() {
    CM_VER=v1.10.0
    curl -sSL -o cmctl.tar.gz https://github.com/cert-manager/cert-manager/releases/download/${CM_VER}/cmctl-linux-amd64.tar.gz
    tar xzf cmctl.tar.gz

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CM_VER}/cert-manager.yaml

    echo waiting for cert-manager deployment
    kubectl -n cert-manager rollout status deploy/cert-manager

    echo waiting for cert-manager-cainjector deployment
    kubectl -n cert-manager rollout status deploy/cert-manager-cainjector

    echo waiting for cert-manager-webhook deployment
    kubectl -n cert-manager rollout status deploy/cert-manager-webhook

    echo waiting for cert-manager api
    ./cmctl --kubeconfig /etc/rancher/k3s/k3s.yaml check api --wait 30s
}

function install() {
    echo installing rancher
    # add rancher repo
    helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
    helm repo update
    # install rancher manager
    helm install rancher rancher-latest/rancher --create-namespace --namespace cattle-system --set bootstrapPassword=admin --version 2.7.0 --set hostname=10-0-40-60.sslip.io --wait

    echo waiting for rancher
    kubectl -n cattle-system rollout status deploy/rancher
    sleep 10

    echo installing elemental-operator
    # install elemental operator
    helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator oci://registry.opensuse.org/isv/rancher/elemental/stable/charts/rancher/elemental-operator-chart --wait

    echo waiting for elemental-operator
    kubectl -n cattle-elemental-system rollout status deploy/elemental-operator

    sleep 10

    echo installing elemental resources
    kubectl apply -f /var/rancher/elemental-res.yaml

    echo installation complete!
}

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo starting install...

echo installing cert-manager
install_cert_manager

sleep 20

echo installing rancher+elemental
install
