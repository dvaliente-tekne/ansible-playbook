#!/bin/bash
set -euo pipefail

# ============================================================================
# Arch Linux Installation Prep Script
# ============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/tmp/prep_$(date '+%Y%m%d_%H%M%S').log"
readonly VALID_HOSTS=("ASTER" "THEMIS" "HEPHAESTUS" "YUGEN")

# Ansible roles to download (common - all hosts)
readonly ANSIBLE_ROLES_COMMON=(
    "https://github.com/dvaliente-tekne/ansible-role-os"
    "https://github.com/dvaliente-tekne/ansible-role-user"
)

# Ansible roles for workstations (ASTER and YUGEN only)
readonly ANSIBLE_ROLES_WORKSTATION=(
    "https://github.com/dvaliente-tekne/ansible-role-xfce4"
    "https://github.com/dvaliente-tekne/ansible-role-onedrive"
    "https://github.com/dvaliente-tekne/ansible-role-gpu"
    "https://github.com/dvaliente-tekne/ansible-role-gaming"
    "https://github.com/dvaliente-tekne/ansible-role-pipewire"
    "https://github.com/dvaliente-tekne/ansible-role-hostname"
    "https://github.com/dvaliente-tekne/ansible-role-bootstrap"
)

# F2FS constants
readonly F2FS_MOUNT_OPTS='compress_algorithm=zstd:6,compress_chksum,atgc,gc_merge,lazytime'
readonly F2FS_MKFS_OPTS='extra_attr,inode_checksum,sb_checksum,compression'

# Host-specific variables (populated by set_host_config)
declare -a arr_drives=()
declare -a arr_partitions=()
declare -a arr_mkfs=()
declare -a arr_filesystems=()
lbaf=0
ses=1
kernel=''
mcode=''
host=''

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*" >&2
    exit 1
}

usage() {
    cat << EOF
Usage: $SCRIPT_NAME <hostname>

Arch Linux installation preparation script.

Supported hosts:
    ASTER       - Laptop with single NVMe
    THEMIS      - Server with dual NVMe  
    HEPHAESTUS  - Workstation with SDA + RAID
    YUGEN       - Workstation with triple NVMe

Options:
    -h, --help  Show this help message

Example:
    $SCRIPT_NAME YUGEN

EOF
    exit 0
}

confirm_destructive() {
    local action="$1"
    echo ""
    echo "ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ"
    echo "â  WARNING: DESTRUCTIVE OPERATION                                  â"
    echo "â âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ£"
    echo "â  Action: $action"
    echo "â  Host:   $host"
    echo "â  Drives: ${arr_drives[*]}"
    echo "ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ"
    echo ""
    read -rp "Type 'YES' to continue: " confirm
    if [[ "$confirm" != "YES" ]]; then
        log "Operation cancelled by user."
        exit 1
    fi
}

connect_wifi() {
    log "TRYING TO CONNECT TO WIFI..."
    if /usr/bin/iwctl station wlan0 connect esher; then
        log "WiFi connection initiated."
    else
        log "WARNING: WiFi connection may have failed."
    fi
}

wait_for_network() {
    local max_attempts="${1:-30}"
    local attempt=0

    log "Waiting for network connectivity..."
    while (( attempt < max_attempts )); do
        if ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
            log "Network is up."
            return 0
        fi
        (( attempt++ ))
        sleep 2
    done
    error "No network connectivity after $max_attempts attempts. Check your connection."
}

clone_or_update_role() {
    local repo_url="$1"
    local roles_dir="$2"
    local repo_name
    repo_name=$(basename "$repo_url")
    local target_dir="${roles_dir}/${repo_name}"
    
    if [[ -d "$target_dir" ]]; then
        log "Role '$repo_name' already exists, pulling latest..."
        if ! git -C "$target_dir" pull --rebase -q; then
            error "Failed to update '$repo_name'. Cannot continue without roles."
        fi
        log "Role '$repo_name' updated."
    else
        log "Cloning '$repo_name' from $repo_url ..."
        if ! git clone "$repo_url" "$target_dir"; then
            error "Failed to clone '$repo_name'. Cannot continue without roles."
        fi
        log "Role '$repo_name' cloned successfully."
    fi
}

download_ansible_roles() {
    log "Downloading Ansible roles from GitHub..."

    # Ensure git is available before attempting to clone/pull repos
    if ! command -v git &>/dev/null; then
        log "git not found, installing..."
        if ! pacman -Sy --noconfirm git; then
            error "Failed to install git. Cannot download Ansible roles."
        fi
    fi
    
    local roles_dir="${SCRIPT_DIR}/roles"
    mkdir -p "$roles_dir"
    
    # Download common roles (all hosts)
    log "Downloading common roles..."
    for repo_url in "${ANSIBLE_ROLES_COMMON[@]}"; do
        clone_or_update_role "$repo_url" "$roles_dir"
    done
    
    # Download workstation roles (ASTER and YUGEN only)
    if [[ "$host" == "ASTER" || "$host" == "YUGEN" ]]; then
        log "Downloading workstation roles for $host..."
        for repo_url in "${ANSIBLE_ROLES_WORKSTATION[@]}"; do
            clone_or_update_role "$repo_url" "$roles_dir"
        done
    fi
    
    log "Ansible roles downloaded to: $roles_dir"
}

validate_host() {
    local input_host="$1"
    for valid in "${VALID_HOSTS[@]}"; do
        if [[ "$input_host" == "$valid" ]]; then
            return 0
        fi
    done
    return 1
}

# ============================================================================
# Host Configuration
# ============================================================================

set_host_config() {
    case "$host" in
        ASTER)
            arr_drives=('nvme0')
            arr_partitions=('nvme0n1')
            arr_mkfs=('nvme0n1p1' 'nvme0n1p2')
            arr_filesystems=('nvme0n1p2' 'nvme0n1p1')
            lbaf=0
            ses=1
            kernel='linux-tkg-alk'
            mcode='sof-firmware laptop-mode-tools-git upd72020x-fw wd719x-firmware ast-firmware aic94xx-firmware blesh-git pikaur'
            connect_wifi
            wait_for_network
            post_pacmanconf
            download_ansible_roles
            ;;
        THEMIS)
            arr_drives=('nvme0' 'nvme1')
            arr_partitions=('nvme0n1' 'nvme1n1')
            arr_mkfs=('nvme0n1p1' 'nvme0n1p2' 'nvme1n1p1')
            arr_filesystems=('nvme0n1p2' 'nvme0n1p1' 'nvme1n1p1')
            lbaf=0
            ses=1
            kernel='linux'
            mcode=''
            connect_wifi
            wait_for_network
            post_pacmanconf
            download_ansible_roles
            ;;
        HEPHAESTUS)
            arr_drives=('sda' 'md126')
            arr_partitions=('sda' 'md126')
            arr_mkfs=('sda1' 'sda2' 'md126p1')
            arr_filesystems=('sda2' 'sda1' 'md126p1')
            lbaf=0
            ses=1
            kernel='linux-tkg-ntl'
            mcode='upd72020x-fw wd719x-firmware ast-firmware aic94xx-firmware blesh-git pikaur'
            connect_wifi
            wait_for_network
            post_pacmanconf
            download_ansible_roles
            ;;
        YUGEN)
            arr_drives=('nvme0' 'nvme1' 'nvme2')
            arr_partitions=('nvme0n1' 'nvme1n1' 'nvme2n1')
            arr_mkfs=('nvme0n1p1' 'nvme0n1p2' 'nvme1n1p1' 'nvme2n1p1')
            arr_filesystems=('nvme0n1p2' 'nvme0n1p1' 'nvme1n1p1' 'nvme2n1p1')
            lbaf=1
            ses=2
            kernel='linux-tkg-ntl'
            mcode='upd72020x-fw wd719x-firmware ast-firmware aic94xx-firmware blesh-git pikaur'
            # YUGEN has no WiFi - requires Ethernet
            wait_for_network
            post_pacmanconf
            download_ansible_roles
            ;;
        *)
            error "Unknown host: '$host'. Valid hosts: ${VALID_HOSTS[*]}"
            ;;
    esac
    log "Host configuration loaded for: $host"
}

# ============================================================================
# Pacman Configuration
# ============================================================================

post_pacmanconf() {
    log "Configuring pacman.conf..."
    
    cat << 'EOF' > /etc/pacman.conf
[options]
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
HoldPkg     = pacman glibc
ParallelDownloads = 100
Architecture = auto
DownloadUser = alpm
VerbosePkgLists
DisableSandbox
CheckSpace
UseSyslog
Color
# IgnorePkg   =
# IgnoreGroup =
# NoUpgrade   =
# NoExtract   =
# NoProgressBar
# CleanMethod = KeepInstalled
# XferCommand = /usr/bin/curl -L -C - -f -o %o %u
# XferCommand = /usr/bin/wget --passive-ftp -c -O %o %u

[core]
Include = /etc/pacman.d/mirrorlist

# [core-testing]
# Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

    if [[ "$host" != 'THEMIS' ]]; then
        cat << 'EOF' >> /etc/pacman.conf

[themis]
SigLevel = Optional TrustAll
Server = http://repo.tekne.sv
EOF
    fi
    
    log "pacman.conf configured."
}

# ============================================================================
# Drive Formatting
# ============================================================================

post_format() {
    if [[ "$host" == 'HEPHAESTUS' ]]; then
        log "Skipping NVMe format for HEPHAESTUS (uses SDA/RAID)."
        return 0
    fi

    confirm_destructive "FORMAT ALL NVME DRIVES"

    for drive in "${arr_drives[@]}"; do
        log "Formatting NVMe drive: /dev/$drive"
        if nvme format /dev/"$drive" --namespace-id=1 --lbaf="$lbaf" --ses="$ses" --ms=1 --reset --force; then
            partprobe
            log "Drive $drive has been formatted successfully."
        else
            error "Failed to format drive: $drive"
        fi
    done
}

# ============================================================================
# Partitioning
# ============================================================================

post_partition() {
    log "Starting drive partitioning..."
    
    confirm_destructive "PARTITION ALL DRIVES"

    # Partition drives
    for partition in "${arr_partitions[@]}"; do
        local parameters=""
        
        case "$partition" in
            nvme0n1|sda)
                parameters="mklabel gpt mkpart esp 0% 1% name 1 'BOOT' mkpart f2fs 1% 100% name 2 'ROOT' set 1 esp on p free"
                ;;
            nvme1n1)
                local partition_name
                if [[ "$host" == 'THEMIS' ]]; then
                    partition_name='VAR'
                else
                    partition_name='HOME'
                fi
                parameters="mklabel gpt mkpart f2fs 1% 100% name 1 '$partition_name' p free"
                ;;
            nvme2n1|md126)
                parameters="mklabel gpt mkpart f2fs 1% 100% name 1 'VAR' p free"
                ;;
            *)
                error "PARTITION FAILED: Unknown drive '$partition'"
                ;;
        esac

        log "Partitioning /dev/$partition..."
        if /usr/bin/parted /dev/"$partition" -a optimal -- $parameters; then
            /usr/bin/partprobe
            log "Drive /dev/$partition has been partitioned."
        else
            error "Failed to partition /dev/$partition"
        fi

        if [[ "$host" == 'ASTER' ]]; then
            log "Partitions for $host are done."
            break
        fi
    done

    # Create filesystems
    log "Creating filesystems..."
    
    for filesystem in "${arr_mkfs[@]}"; do
        case "$filesystem" in
            nvme0n1p1|sda1)
                log "Creating FAT32 filesystem on /dev/$filesystem..."
                /usr/bin/mkfs.vfat -F32 -n 'BOOT' /dev/"$filesystem"
                ;;
            nvme0n1p2|sda2)
                log "Creating F2FS filesystem (ROOT) on /dev/$filesystem..."
                /usr/bin/mkfs.f2fs -l 'ROOT' -i -O "$F2FS_MKFS_OPTS" /dev/"$filesystem"
                ;;
            nvme1n1p1)
                local filesystem_name
                if [[ "$host" == 'THEMIS' ]]; then
                    filesystem_name='VAR'
                else
                    filesystem_name='HOME'
                fi
                log "Creating F2FS filesystem ($filesystem_name) on /dev/$filesystem..."
                /usr/bin/mkfs.f2fs -l "$filesystem_name" -i -O "$F2FS_MKFS_OPTS" /dev/"$filesystem"
                ;;
            nvme2n1p1|md126p1)
                log "Creating F2FS filesystem (VAR) on /dev/$filesystem..."
                /usr/bin/mkfs.f2fs -l 'VAR' -i -O "$F2FS_MKFS_OPTS" /dev/"$filesystem"
                ;;
            *)
                error "FILESYSTEM FAILED: Unknown partition '$filesystem'"
                ;;
        esac
        /usr/bin/partprobe

        if [[ "$host" == 'ASTER' ]] && [[ "$filesystem" == 'nvme0n1p2' ]]; then
            log "Filesystems created for $host."
            break
        fi
    done
    
    log "Partitioning and filesystem creation complete."
}

# ============================================================================
# Mount Filesystems
# ============================================================================

post_mount() {
    log "Mounting filesystems..."

    for filesystem in "${arr_filesystems[@]}"; do
        case "$filesystem" in
            nvme0n1p2|sda2)
                log "Mounting ROOT filesystem: /dev/$filesystem -> /mnt"
                /usr/bin/mount -o "$F2FS_MOUNT_OPTS" /dev/"$filesystem" /mnt
                /usr/bin/mkdir -p /mnt/{boot,home,media,var}
                ;;
            nvme0n1p1|sda1)
                log "Mounting BOOT filesystem: /dev/$filesystem -> /mnt/boot"
                /usr/bin/mount /dev/"$filesystem" /mnt/boot
                ;;
            nvme1n1p1)
                local folder
                if [[ "$host" == 'THEMIS' ]]; then
                    folder='var'
                else
                    folder='home'
                fi
                log "Mounting $folder filesystem: /dev/$filesystem -> /mnt/$folder"
                /usr/bin/mount -o "$F2FS_MOUNT_OPTS" /dev/"$filesystem" /mnt/"$folder"
                ;;
            nvme2n1p1|md126p1)
                log "Mounting VAR filesystem: /dev/$filesystem -> /mnt/var"
                /usr/bin/mount -o "$F2FS_MOUNT_OPTS" /dev/"$filesystem" /mnt/var
                ;;
            *)
                error "MOUNT FAILED: Unknown partition '$filesystem'"
                ;;
        esac
        partprobe
    done
    
    log "All filesystems mounted."
}

# ============================================================================
# Chroot Configuration
# ============================================================================

post_chroot_config() {
    log "Configuring system inside chroot..."

    # Ensure chroot uses our pacman.conf (mirrorlist, [themis], etc.)
    cp /etc/pacman.conf /mnt/etc/pacman.conf
    chown root:users /mnt/etc/pacman.conf

    # Determine boot disk based on host
    local boot_disk
    case "$host" in
        ASTER|THEMIS|YUGEN) boot_disk="/dev/nvme0n1" ;;
        HEPHAESTUS) boot_disk="/dev/sda" ;;
    esac

    arch-chroot /mnt /bin/bash <<CHROOT_EOF
set -euo pipefail

# Timezone & clock
ln -sf /usr/share/zoneinfo/America/El_Salvador /etc/localtime
hwclock --systohc

# Locale
sed -i 's|#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|g' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf

# EFI boot entry (remove old entry if it exists)
/usr/bin/efibootmgr -B -b 0 2>/dev/null || true

/usr/bin/efibootmgr \
    --disk ${boot_disk} \
    --part 1 \
    --create \
    --label BOOT \
    --loader /vmlinuz-${kernel} \
    --unicode " root=LABEL=ROOT rw initrd=\intel-ucode.img initrd=\initramfs-${kernel}.img enable_guc=3 intel_pstate=passive kernel.split_lock_mitigate=0 split_lock_detect=off nowatchdog mitigations=off quiet loglevel=2 systemd.show_status=false rd.udev.log_level=2"

# Generate initramfs
mkinitcpio -p ${kernel}

echo "Automated chroot configuration complete."
CHROOT_EOF

    log "Entering interactive chroot for password setup..."
    arch-chroot /mnt
}

# ============================================================================
# System Installation
# ============================================================================

post_start() {
    log "Starting system installation..."
    
    sed -i 's|#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|g' /etc/locale.gen

    post_pacmanconf

    # Re-check internet before downloading packages
    wait_for_network
    
    # Set NTP after network is confirmed up
    /usr/bin/timedatectl set-ntp true

    log "Synchronizing package databases..."
    pacman -Syy

    log "Installing base system with pacstrap..."
    /usr/bin/pacstrap -K /mnt base base-devel \
        intel-ucode $mcode $kernel "${kernel}-headers" \
        linux-firmware linux-firmware-broadcom linux-firmware-liquidio linux-firmware-mellanox \
        linux-firmware-nfp linux-firmware-qlogic \
        dosfstools f2fs-tools exfatprogs exfat-utils \
        ansible-core ansible-lint ansible \
        python python-pip python-pipx python-passlib \
        vim vim-vital vim-tagbar vim-tabular vim-syntastic vim-supertab vim-spell-es vim-spell-en \
        vim-nerdtree vim-nerdcommenter vim-indent-object vim-gitgutter vim-devicons vim-ansible \
        mlocate bash-completion pkgfile efibootmgr acpi acpid iwd wpa_supplicant \
        wireless-regdb rsync git wget reflector iptables-nft less usb_modeswitch libsecret gzip tar zlib xz \
        nvme-cli openssh openssl screen sudo gnupg bind cronie inetutils whois zip unzip p7zip sed fuse \
	mdadm jq curl make pkg-config dbus openbsd-netcat irqbalance schedtool schedtoold pikaur

    log "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    cp /mnt/etc/fstab /mnt/etc/fstab.origin
    sed -i 's|relatime|noatime|g' /mnt/etc/fstab

    ln -sf /usr/bin/vim /mnt/usr/bin/vi
    ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

    mv /mnt/etc/pacman.conf /mnt/etc/pacman.bak
    cp /etc/pacman.conf /mnt/etc/pacman.conf
    chown root:users /mnt/etc/pacman.conf

    echo "127.0.0.1 localhost $host.tekne.sv $host" >> /mnt/etc/hosts
    echo "$host" > /mnt/etc/hostname

    # Mount media partition only on hosts that have /dev/sda3
    if [[ "$host" == 'ASTER' || "$host" == 'HEPHAESTUS' ]]; then
        if [[ -b /dev/sda3 ]]; then
            log "Mounting media partition /dev/sda3 -> /mnt/media"
            mount /dev/sda3 /mnt/media
        else
            log "WARNING: /dev/sda3 not found, skipping media mount."
        fi
    fi

    if [[ "$host" == 'HEPHAESTUS' ]]; then
        log "Configuring mdadm for RAID..."
        mdadm --detail --scan >> /mnt/etc/mdadm.conf
    fi

    log "Installation complete. Configuring chroot..."
    log "Log file saved to: $LOG_FILE"
    
    post_chroot_config
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
    fi

    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root."
    fi

    # Validate hostname argument
    if [[ -z "${1:-}" ]]; then
        echo "ERROR: Hostname argument required."
        echo ""
        usage
    fi

    host="$1"

    if ! validate_host "$host"; then
        error "Invalid host: '$host'. Valid hosts: ${VALID_HOSTS[*]}"
    fi

    log "============================================================"
    log "Arch Linux Installation Script Started"
    log "Host: $host"
    log "Log file: $LOG_FILE"
    log "============================================================"

    # Load host configuration
    set_host_config

    # Execute installation steps
    post_format
    post_partition
    post_mount
    post_start
}

main "$@"
