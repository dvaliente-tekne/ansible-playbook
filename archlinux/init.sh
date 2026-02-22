#!/bin/bash

ansible-playbook ./main.yml --tags os,pipewire,gaming,onedrive,bootstrap --ask-vault-pass -e@vault