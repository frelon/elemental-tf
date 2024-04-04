#!/bin/bash
mac_address="52:54:00:$(dd if=/dev/urandom bs=512 count=1 2>/dev/null \
                           | md5sum \
                           | sed -E 's/^(..)(..)(..).*$/\1:\2:\3/')"
echo $mac_address
