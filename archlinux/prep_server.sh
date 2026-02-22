#!/bin/bash

ansible-playbook /media/ansible-playbook/archlinux/main.yml --tags user,gpu --ask-vault-pass -e@/media/ansible-playbook/archlinux/vault