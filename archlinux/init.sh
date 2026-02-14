#!/bin/bash

ansible-playbook ./workstation.yml --tags os,pipewire,gaming,onedrive,bootstrap --ask-vault-pass -e@vault