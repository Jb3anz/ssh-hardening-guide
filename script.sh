#!/usr/bin/env bash
#
# ssh-hardening-setup.sh
#
# WARNING:
# This script changes SSH authentication and firewall settings.
# Always keep your current SSH session open until you have successfully
# tested a NEW SSH connection using the new sudo user.
#
# Interactive companion script for the SSH hardening guide.
# Run this AS ROOT on a fresh Debian/Ubuntu VPS.
#
# Phase 1: install sshd if needed, create a non-root sudo user, deploy
#          your public key, and check permissions.
# --- STOP AND TEST LOGIN AS THE NEW USER IN A FRESH TERMINAL ---
# Phase 2: harden sshd_config, set up UFW, set up fail2ban.
#
# Phase 2 will refuse to run until you confirm you've tested login.
# This script does not generate keys for you — generate your ed25519
# keypair locally first (ssh-keygen -t ed25519) and have the PUBLIC
# key (the .pub file contents) ready to paste in.

set -euo pipefail

STATE_FILE="/root/.ssh-hardening-setup.state"

# ---------- helpers ----------

log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\n\033[1;33m!!\033[0m %s\n' "$1"; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Run this script as root (e.g. sudo ./script.sh)."
    fi
}

require_apt() {
    if ! command -v apt >/dev/null 2>&1; then
        die "This script only supports Debian/Ubuntu (apt) systems."
    fi
}

state_get() { grep -m1 "^$1=" "$STATE_FILE" 2>/dev/null | cut -d= -f2- || true; }
state_set() {
    touch "$STATE_FILE"
    if grep -q "^$1=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s#^$1=.*#$1=$2#" "$STATE_FILE"
    else
        echo "$1=$2" >> "$STATE_FILE"
    fi
}

# ---------- phase 1 ----------

check_sshd_installed() {
    log "Checking whether openssh-server is installed..."
    if command -v sshd >/dev/null 2>&1; then
        echo "openssh-server is already installed."
    else
        echo "openssh-server not found, installing it now."
        apt update
        apt install -y openssh-server
    fi
    systemctl enable --now ssh
}

create_sudo_user() {
    local username
    read -rp "Enter the username for the new non-root sudo user: " username

    if [[ -z "$username" ]]; then
        die "Username cannot be empty."
    fi

    if id "$username" &>/dev/null; then
        warn "User '$username' already exists, skipping creation."
    else
        log "Creating user '$username'..."
        # adduser will prompt you to set a local password for this account.
        # That's fine, it's only used for local/sudo purposes, remote SSH
        # password login gets disabled in phase 2 regardless.
        adduser --gecos "" "$username"
        usermod -aG sudo "$username"
    fi

    state_set SSH_USER "$username"
}

deploy_public_key() {
    local username home_dir pubkey
    username="$(state_get SSH_USER)"
    home_dir="/home/${username}"

    log "Paste the CONTENTS of your PUBLIC key file (id_ed25519.pub)."
    echo "This should be a single line starting with 'ssh-ed25519 ...'"
    echo "Do NOT paste your private key."
    read -rp "Public key: " pubkey

    if [[ -z "$pubkey" ]]; then
        die "No key entered."
    fi
    if [[ "$pubkey" != ssh-* ]]; then
        die "That doesn't look like a public key (should start with 'ssh-ed25519', 'ssh-rsa', etc.)."
    fi

    mkdir -p "${home_dir}/.ssh"

    if [[ -f "${home_dir}/.ssh/authorized_keys" ]] && grep -qF "$pubkey" "${home_dir}/.ssh/authorized_keys"; then
        warn "That key is already present in authorized_keys, skipping."
    else
        echo "$pubkey" >> "${home_dir}/.ssh/authorized_keys"
        echo "Key added to ${home_dir}/.ssh/authorized_keys"
    fi

    chown -R "${username}:${username}" "${home_dir}/.ssh"
    chmod 700 "${home_dir}/.ssh"
    chmod 600 "${home_dir}/.ssh/authorized_keys"
}

phase1() {
    require_root
    require_apt
    check_sshd_installed
    create_sudo_user
    deploy_public_key
    state_set PHASE1_DONE yes

    local username
    username="$(state_get SSH_USER)"

    warn "PHASE 1 COMPLETE. DO NOT CLOSE THIS SESSION."
    echo
    echo "Open a BRAND NEW terminal and confirm you can log in with:"
    echo "    ssh ${username}@your_server_ip"
    echo
    echo "IMPORTANT: if your private key file is NOT the default name"
    echo "(id_ed25519, id_rsa, etc.), plain 'ssh user@host' will NOT offer it"
    echo "automatically and will silently fall back to a password prompt,"
    echo "which looks like success but means your key isn't actually being used."
    echo "Either connect with -i explicitly:"
    echo "    ssh -i /path/to/your/key ${username}@your_server_ip"
    echo "or add a Host entry to your local ~/.ssh/config (or"
    echo "C:\\Users\\you\\.ssh\\config on Windows) with an IdentityFile line."
    echo
    echo "If SSH ever asks you for a 'password:' during this test, that means"
    echo "the key did NOT work, stop and fix that before running --phase2."
    echo
    echo "Once you've confirmed that works, come back here and re-run this"
    echo "script with the --phase2 flag to continue with hardening."
}

# ---------- phase 2 ----------

confirm_tested_login() {
    if [[ "$(state_get PHASE1_DONE)" != "yes" ]]; then
        die "Phase 1 hasn't been run yet. Run this script without flags first."
    fi

    local username answer
    username="$(state_get SSH_USER)"

    warn "Before continuing: have you opened a NEW terminal and successfully"
    echo "logged in as '${username}' with your key?"
    echo
    echo "IMPORTANT: if SSH asked you for a 'password:' at any point, that means"
    echo "your key did NOT work and it silently fell back to password auth."
    echo "Only a passphrase prompt for YOUR KEY ITSELF (if you set one) is fine."
    echo "If you saw a plain 'password:' prompt, answer 'no' below and go fix"
    echo "your authorized_keys setup first, do not continue."
    echo
    read -rp "Type 'yes' to confirm and continue: " answer

    if [[ "$answer" != "yes" ]]; then
        die "Aborting. Go test that login first, this step exists to stop you locking yourself out."
    fi
}

harden_sshd_config() {
    log "Backing up sshd_config..."
    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"

    log "Applying hardening settings..."
    local cfg="/etc/ssh/sshd_config"
    declare -A settings=(
        [PasswordAuthentication]=no
        [PermitRootLogin]=no
        [PermitEmptyPasswords]=no
    )

    for key in "${!settings[@]}"; do
        local value="${settings[$key]}"
        if grep -qE "^\s*#?\s*${key}\b" "$cfg"; then
            sed -i -E "s/^\s*#?\s*(${key})\s+.*/\1 ${value}/" "$cfg"
        else
            echo "${key} ${value}" >> "$cfg"
        fi
    done

    # also patch any drop-in override files, since these win over sshd_config
    if [[ -d /etc/ssh/sshd_config.d ]]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [[ -e "$f" ]] || continue
            for key in "${!settings[@]}"; do
                if grep -qE "^\s*${key}\b" "$f"; then
                    warn "Found '${key}' set in ${f}, review it manually, drop-ins override sshd_config."
                fi
            done
        done
    fi

    log "Validating config syntax..."
    if ! sshd -t; then
        die "sshd -t reported a config error. Restore the backup and fix it before reloading."
    fi

    log "Confirming the settings actually took effect (checking effective config, not just what we wrote)..."
    local effective
    if ! effective="$(sshd -T 2>&1)"; then
        warn "sshd -T failed while checking effective config, here's the error:"
        echo "$effective"
        die "Fix the sshd_config error above before continuing."
    fi
    for key in "${!settings[@]}"; do
        local want="${settings[$key]}"
        local lower_key got
        lower_key="$(echo "$key" | tr '[:upper:]' '[:lower:]')"
        got="$(echo "$effective" | awk -v k="$lower_key" '$1 == k {print $2; exit}')"
        if [[ "$got" != "$want" ]]; then
            warn "${key} is effectively '${got:-unset}', not '${want}'. Something (likely a file in /etc/ssh/sshd_config.d/) is overriding it. Check with: sudo sshd -T | grep -i ${lower_key}"
        fi
    done

    log "Reloading ssh service..."
    systemctl reload ssh
    echo "sshd_config hardened and reloaded."
}

setup_ufw() {
    local answer ssh_port
    read -rp "Set up UFW firewall now? [Y/n]: " answer
    answer="${answer:-Y}"
    [[ "$answer" =~ ^[Yy] ]] || { echo "Skipping UFW."; return; }

    log "Detecting the actual SSH port sshd is configured to use..."
    local sshd_output
    if ! sshd_output="$(sshd -T 2>&1)"; then
        warn "sshd -T failed, here's the error:"
        echo "$sshd_output"
        warn "Falling back to port 22, override below if that's wrong."
        ssh_port=22
    else
        ssh_port="$(echo "$sshd_output" | awk '$1 == "port" {print $2; exit}')"
        ssh_port="${ssh_port:-22}"
    fi
    echo "Detected SSH port: ${ssh_port}"

    read -rp "Does that look right? Press enter to accept, or type a different port: " override
    ssh_port="${override:-$ssh_port}"

    log "Installing UFW..."
    apt install -y ufw

    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${ssh_port}/tcp"

    log "Enabling UFW (allowing port ${ssh_port} first, so you won't be locked out)..."
    ufw --force enable
    ufw status verbose
}

setup_fail2ban() {
    local answer
    read -rp "Set up fail2ban now? [Y/n]: " answer
    answer="${answer:-Y}"
    [[ "$answer" =~ ^[Yy] ]] || { echo "Skipping fail2ban."; return; }

    log "Installing fail2ban..."
    apt install -y fail2ban

    cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h
EOF

    systemctl enable --now fail2ban
    fail2ban-client status sshd || warn "fail2ban-client status check failed, check 'systemctl status fail2ban'."
}

phase2() {
    require_root
    require_apt
    confirm_tested_login
    harden_sshd_config
    setup_ufw
    setup_fail2ban

    log "All done."
    echo "Recap of what changed:"
    echo "  - PasswordAuthentication, PermitRootLogin, PermitEmptyPasswords set to no"
    echo "  - sshd_config backed up before editing"
    echo "  - UFW and fail2ban configured (if you opted in)"
    echo
    echo "Keep your current session open and open a fresh one to do a final login test."
}

# ---------- entrypoint ----------

case "${1:-}" in
    --phase2)
        phase2
        ;;
    "")
        phase1
        ;;
    *)
        echo "Usage: $0 [--phase2]"
        echo "  (no flag)  run phase 1: create user, deploy key"
        echo "  --phase2   run phase 2: harden sshd_config, UFW, fail2ban"
        exit 1
        ;;
esac
