#!/bin/sh
VERSION=1.1.4
helm upgrade --create-namespace -n cattle-elemental-system --set image.repository=frallan/elemental-operator --install elemental-operator ../elemental-operator/build/elemental-operator-${VERSION}.tgz
