#!/bin/bash

ansible-playbook /media/ansible-playbook/archlinux/workstation.yml --tags user,xfce4 --ask-vault-pass -e@vault