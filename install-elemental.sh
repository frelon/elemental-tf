#!/bin/sh
helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator-crds oci://registry.suse.com/rancher/elemental-operator-crds-chart
helm upgrade --create-namespace -n cattle-elemental-system --install elemental-operator oci://registry.suse.com/rancher/elemental-operator-chart
