#!/bin/bash

ansible-playbook workstation.yml --tags user, xfce4 --ask-vault-pass -e@vault