#!/bin/bash

set -e

function install_cert_manager() {
    echo installing cert-manager

    CM_VER=v1.7.1
    # curl -sSL -o cmctl.tar.gz https://github.com/cert-manager/cert-manager/releases/download/${CM_VER}/cmctl-linux-amd64.tar.gz
    # tar xzf cmctl.tar.gz

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CM_VER}/cert-manager.yaml

    echo waiting for cert-manager deployment
    kubectl -n cert-manager rollout status deploy/cert-manager

    echo waiting for cert-manager-cainjector deployment
    kubectl -n cert-manager rollout status deploy/cert-manager-cainjector

    echo waiting for cert-manager-webhook deployment
    kubectl -n cert-manager rollout status deploy/cert-manager-webhook

    echo waiting for cert-manager api
    cmctl --kubeconfig ./k3s.yaml check api --wait 30s
}

function install() {
    echo installing rancher
    # add rancher repo
    helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
    helm repo update
    # install rancher manager
    helm upgrade --install rancher rancher-latest/rancher \
        --create-namespace --namespace cattle-system \
        --version 2.8.2 \
        --set hostname=10-0-40-60.sslip.io \
        --set global.cattle.psp.enabled=false \
        --set extraEnv[0].name=CATTLE_SERVER_URL \
	--set extraEnv[0].value=https://10-0-40-60.sslip.io \
	--set extraEnv[1].name=CATTLE_BOOTSTRAP_PASSWORD \
	--set extraEnv[1].value=admin \
        --wait

    echo waiting for rancher
    kubectl -n cattle-system rollout status deploy/rancher

    echo installation complete!
}

echo starting install...

install_cert_manager

install
