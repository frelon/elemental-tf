#!/bin/sh
VERSION=1.1.1
helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator https://github.com/rancher/elemental-operator/releases/download/v${VERSION}/elemental-operator-${VERSION}.tgz
