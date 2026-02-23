#!/bin/bash

ansible-playbook main.yml --tags os,docker,libvirt,nftables,haproxy,repotekne --ask-vault-pass -e@vault