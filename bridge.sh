#!/bin/bash

ACTION=$1

# iptables -I FORWARD -m physdev --physdev-is-bridged -j ACCEPT

case $ACTION in
up)
  nmcli con add ifname vbr0 type bridge con-name vbr0
  nmcli con add type bridge-slave ifname enp2s0f0 master vbr0
  nmcli con mod vbr0 bridge.stp no
  # nmcli con mod vbr0 ipv4.addresses 10.0.40.16/24
  # nmcli con mod vbr0 ipv4.gateway 10.0.40.1
  # nmcli con mod vbr0 ipv4.dns '10.0.40.1'
  nmcli con up vbr0
  ;;
down)
  nmcli con down vbr0
  nmcli con delete vbr0
  ;;
esac
