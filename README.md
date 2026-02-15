# Ansible Playbooks

Documentation for playbooks in this directory. Playbooks are grouped by target OS or environment.

## Directory Layout

```
ansible-playbook/
├── README.md           # This file – playbook documentation
└── archlinux/          # Arch Linux playbooks and runtime files
    ├── ansible.cfg     # Ansible config (inventory, roles path, fact cache)
    ├── inventory.yml   # Inventory (localhost for workstation)
    ├── vault           # Encrypted variables (ansible-vault)
    ├── workstation.yml # Workstation playbook
    ├── prep.sh         # Live-ISO prep and base install
    ├── chroot.sh       # Chroot install helper
    ├── init.sh         # Optional init script
    └── README.md       # Arch Linux setup and usage guide
```

Roles are resolved from `./roles` (under `archlinux/`, populated by `prep.sh`) and `../../roles` (repo roles for development). See `archlinux/ansible.cfg`.

---

## Playbooks

### archlinux/workstation.yml

| Property | Value |
|----------|--------|
| **Path** | `archlinux/workstation.yml` |
| **Purpose** | Full workstation configuration for Arch Linux (users, OS, audio, GPU, desktop, gaming, OneDrive, bootstrap). |
| **Target hosts** | `localhost` (connection: local). |
| **Allowed hostnames** | **ASTER** or **YUGEN** only (enforced in pre_tasks). |
| **Privilege** | `become: true` (root). |
| **Vault** | Yes – `vars_files: [vault]`. |

#### Pre-tasks

Run before any role:

1. **Hostname detection** – Read `/etc/hostname`, set `current_hostname` / `current_hostname_raw` (normalized to uppercase for checks).
2. **Hostname check** – Assert `current_hostname in ['ASTER', 'YUGEN']`; fail with a clear message otherwise.
3. **Hostname facts** – Set `cached_hostname`, `cached_hostname_raw`, `hostname` (cacheable) for roles.
4. **Host-specific bootstrap** – Set `bootstrap_xfce_monitors` per host:
   - **ASTER:** `eDP-1`, `DP-1-1`
   - **YUGEN:** `DP-1`, `DP-2`, `DP-3`

#### Roles (execution order)

| Order | Role | Tag | Description |
|-------|------|-----|-------------|
| 1 | ansible-role-user | `user` | Users, SSH keys, shell configs, sudoers, dotfiles |
| 2 | ansible-role-os | `os` | Locale, network (systemd-networkd), NTP, mirrors, services |
| 3 | ansible-role-pipewire | `pipewire` | PipeWire audio stack and configuration |
| 4 | ansible-role-gpu | `gpu` | Graphics drivers (NVIDIA on YUGEN, Intel/Mesa on ASTER) |
| 5 | ansible-role-xfce4 | `xfce4` | XFCE4 desktop, themes, LightDM (ASTER), bluetooth-related packages |
| 6 | ansible-role-gaming | `gaming` | Steam, Lutris, Wine/Proton, gamemode |
| 7 | ansible-role-onedrive | `onedrive` | OneDrive client (abraunegg) install and setup |
| 8 | ansible-role-bootstrap | `bootstrap` | OneDrive sync (interactive), symlinks, XFCE panel/monitor config |

**Note:** The bootstrap role can pause for OneDrive authentication; follow the on-screen steps to sign in with Microsoft.

#### How to run

From `ansible-playbook/archlinux/`:

```bash
# Full run (vault password prompted)
ansible-playbook workstation.yml --ask-vault-pass

# Using a vault password file
ansible-playbook workstation.yml --vault-password-file=~/.vault_pass

# Only specific roles (comma-separated tags)
ansible-playbook workstation.yml --ask-vault-pass --tags "user,os,xfce4"

# Check mode (no changes)
ansible-playbook workstation.yml --ask-vault-pass --check

# Verbose
ansible-playbook workstation.yml --ask-vault-pass -vv
```

#### Tags summary

| Tag | Roles / scope |
|-----|----------------|
| `user` | ansible-role-user |
| `os` | ansible-role-os |
| `pipewire` | ansible-role-pipewire |
| `gpu` | ansible-role-gpu |
| `xfce4` | ansible-role-xfce4 |
| `gaming` | ansible-role-gaming |
| `onedrive` | ansible-role-onedrive |
| `bootstrap` | ansible-role-bootstrap |

---

## Running a playbook

1. **From the playbook directory** (so `ansible.cfg` and paths apply):

   ```bash
   cd ansible-playbook/archlinux
   ansible-playbook workstation.yml --ask-vault-pass
   ```

2. **Vault:** Playbooks that use `vars_files: [vault]` need a vault password via `--ask-vault-pass` or `--vault-password-file`.

3. **Inventory:** `archlinux` playbooks use `inventory.yml` (see `ansible.cfg`), which targets `localhost` with `ansible_connection: local`.

For first-time Arch install, WiFi, partitioning, and base system, see **archlinux/README.md** and `prep.sh`.
