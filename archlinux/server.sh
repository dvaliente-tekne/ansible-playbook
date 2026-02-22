#!/bin/bash

ansible-playbook main.yml --tags os,docker,libvirt,nftables --ask-vault-pass -e@vault