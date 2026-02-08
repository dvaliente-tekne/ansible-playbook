#!/bin/bash

ansible-playbook workstation.yml --tags user, os, pipewire, gpu, xfce4, gaming, onedrive, bootstrap--ask-vault-pass -e@vault