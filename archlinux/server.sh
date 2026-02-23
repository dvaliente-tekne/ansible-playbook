#!/bin/bash

ansible-playbook main.yml --tags os,docker,libvirt,nftables,haproxy --ask-vault-pass -e@vault