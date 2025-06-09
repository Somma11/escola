#!/bin/bash

# --- IMPORTANT: READ BEFORE RUNNING ---
# This script installs Cockpit and its useful modules, configures the firewall,
# and provides security tips.
# It requires sudo privileges.
# ALWAYS review the script before executing it.

# Function to display error and exit
function error_exit {
    echo "Error: $1" >&2
    exit 1
}

echo "Starting Cockpit installation and configuration..."

# --- 1. Identify Distribution ---
DISTRO=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
elif type lsb_release >/dev/null 2>&1; then
    DISTRO=$(lsb_release -si)
elif [ -f /etc/redhat-release ]; then
    DISTRO="rhel" # Generic for RHEL-based
elif [ -f /etc/debian_version ]; then
    DISTRO="debian" # Generic for Debian-based
else
    error_exit "Could not identify Linux distribution. Exiting."
fi

echo "Identified distribution: $DISTRO"

# --- 2. Install Cockpit and Useful Modules ---
echo "Installing Cockpit and useful modules (cockpit-machines, cockpit-docker)..."
case "$DISTRO" in
    ubuntu|debian|pop|mint)
        sudo apt update || error_exit "apt update failed."
        sudo apt install -y cockpit cockpit-machines cockpit-docker || error_exit "Failed to install Cockpit and modules."
        ;;
    fedora|centos|rhel|almalinux|rocky)
        sudo dnf check-update || error_exit "dnf check-update failed."
        sudo dnf install -y cockpit cockpit-machines cockpit-docker || error_exit "Failed to install Cockpit and modules."
        ;;
    arch|manjaro)
        sudo pacman -Sy --noconfirm cockpit cockpit-machines cockpit-podman # Arch uses podman instead of docker module
        if [ $? -ne 0 ]; then
             echo "Warning: cockpit-docker not found, attempting cockpit-podman."
             # Try installing cockpit-docker if available, or just proceed
             sudo pacman -Sy --noconfirm cockpit cockpit-machines || error_exit "Failed to install Cockpit and modules."
        fi
        ;;
    *)
        error_exit "Unsupported distribution for Cockpit installation: $DISTRO"
        ;;
esac
echo "Cockpit and modules installed."

# --- 3. Enable and Start Cockpit Socket ---
echo "Enabling and starting Cockpit socket..."
sudo systemctl enable --now cockpit.socket || error_exit "Failed to enable/start cockpit.socket."
echo "Cockpit socket enabled and started."

# --- 4. Configure Firewall ---
echo "Configuring firewall to allow Cockpit access (port 9090)..."
case "$DISTRO" in
    ubuntu|debian|pop|mint)
        # Check if UFW is active
        if sudo ufw status | grep -q "Status: active"; then
            sudo ufw allow 9090/tcp || error_exit "Failed to allow port 9090 in UFW."
            sudo ufw reload # Reload UFW to apply changes
            echo "UFW configured for Cockpit."
        else
            echo "UFW is not active or installed. Skipping UFW configuration. Please configure your firewall manually."
        fi
        ;;
    fedora|centos|rhel|almalinux|rocky)
        sudo firewall-cmd --add-service=cockpit --permanent || error_exit "Failed to add cockpit service to firewalld."
        sudo firewall-cmd --reload || error_exit "Failed to reload firewalld."
        echo "Firewalld configured for Cockpit."
        ;;
    arch|manjaro)
        # Assuming systemd-networkd + iptables/nftables or firewalld
        if command -v firewall-cmd &> /dev/null; then
            sudo firewall-cmd --add-service=cockpit --permanent || error_exit "Failed to add cockpit service to firewalld."
            sudo firewall-cmd --reload || error_exit "Failed to reload firewalld."
            echo "Firewalld configured for Cockpit."
        elif command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
            sudo ufw allow 9090/tcp || error_exit "Failed to allow port 9090 in UFW."
            sudo ufw reload # Reload UFW to apply changes
            echo "UFW configured for Cockpit."
        else
            echo "No common firewall detected (firewalld/ufw). Skipping firewall configuration. Please configure your firewall manually."
        fi
        ;;
    *)
        echo "Unsupported distribution for automatic firewall configuration. Please configure your firewall manually."
        ;;
esac
echo "Firewall configuration attempted."

# --- 5. Optional: Configure Cockpit Session Timeout ---
echo "Configuring Cockpit session timeout (optional)..."
# Set timeout to 15 minutes (900 seconds)
# This creates/modifies a drop-in file for cockpit.socket
# Check if the directory exists, if not, create it
if [ ! -d "/etc/systemd/system/cockpit.socket.d" ]; then
    sudo mkdir -p /etc/systemd/system/cockpit.socket.d
fi

echo "[Socket]" | sudo tee /etc/systemd/system/cockpit.socket.d/timeout.conf > /dev/null
echo "IdleTimeoutSec=900" | sudo tee -a /etc/systemd/system/cockpit.socket.d/timeout.conf > /dev/null
echo "Cockpit session timeout set to 15 minutes."
sudo systemctl daemon-reload
sudo systemctl restart cockpit.socket

echo "--- Cockpit Installation Complete ---"
echo "You can now access Cockpit via your web browser at: https://$(hostname -I | awk '{print $1}'):9090"
echo "Use your system username and password to log in."

echo ""
echo "--- Important Security Considerations ---"
echo "1. Use strong, unique passwords for your system users."
echo "2. Keep your system updated regularly: 'sudo apt update && sudo apt upgrade' or 'sudo dnf update' or 'sudo pacman -Syu'."
echo "3. Consider setting up Two-Factor Authentication (2FA) for SSH and potentially Cockpit if available."
echo "4. Restrict SSH access to specific IPs (if possible) in /etc/ssh/sshd_config."
echo "5. For production environments, consider using a reverse proxy (like Nginx or Apache) with TLS/SSL for Cockpit access,"
echo "   though Cockpit provides its own self-signed certificate by default."
echo "6. Only install modules you actually need."
echo "7. Regularly review logs (accessible via Cockpit) for suspicious activity."
echo "---------------------------------------"
