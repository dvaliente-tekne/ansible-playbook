#!/bin/bash

# sudo ansible-playbook main.yml --tags os,docker,libvirt,nftables,haproxy,repotekne --ask-vault-pass -e@vault
sudo ansible-playbook main.yml --tags repotekne --ask-vault-pass -e@vault
