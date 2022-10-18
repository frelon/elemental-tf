#!/bin/bash
ip link set enp2s0f0 nomaster
ip link set vbr0 down
ip link del vbr0
