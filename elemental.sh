#!/bin/sh

export KUBECONFIG=${KUBECONFIG:="./k3s.yaml"}

ACTION=$1
CHANNEL=$2

case $ACTION in
uninstall)
  helm uninstall -n cattle-elemental-system elemental-operator
  helm uninstall -n cattle-elemental-system elemental-operator-crds
  exit 0
  ;;
install)
  ;;
*)
  echo "Unknown action $ACTION"
  exit 1
  ;;
esac

case $CHANNEL in
dev)
  helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator-crds oci://registry.opensuse.org/isv/rancher/elemental/dev/charts/rancher/elemental-operator-crds-chart
  helm upgrade --create-namespace -n cattle-elemental-system --install --set image.imagePullPolicy=Always elemental-operator oci://registry.opensuse.org/isv/rancher/elemental/dev/charts/rancher/elemental-operator-chart
  ;;
staging)
  helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator-crds oci://registry.opensuse.org/isv/rancher/elemental/staging/charts/rancher/elemental-operator-crds-chart
  helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator oci://registry.opensuse.org/isv/rancher/elemental/staging/charts/rancher/elemental-operator-chart
  ;;
*)
  helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator-crds oci://registry.suse.com/rancher/elemental-operator-crds-chart
  helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator oci://registry.suse.com/rancher/elemental-operator-chart
  ;;
esac


