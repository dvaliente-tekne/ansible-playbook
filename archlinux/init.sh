#!/bin/bash

ansible-playbook ./workstation.yml --tags os,pipewire,gpu,gaming,onedrive,bootstrap --ask-vault-pass -e@vault