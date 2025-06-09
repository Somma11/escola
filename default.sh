#!/bin/bash

# --- IMPORTANT: READ BEFORE RUNNING ---
# This script attempts to identify your Linux distribution and install several packages,
# including Cockpit with a good default configuration.
# Full automation of complex services like Gitea and phpMyAdmin (especially with PostgreSQL)
# is very challenging and this script provides basic installation.
# Extensive manual configuration and security hardening will be REQUIRED after running.
# ALWAYS review the script and understand what it does before executing it.
# This script requires sudo privileges.

# Function to display error and exit
function error_exit {
    echo "Error: $1" >&2
    exit 1
}

# Function to check if a package is installed
function is_package_installed {
    case "$DISTRO" in
        ubuntu|debian|pop|mint)
            dpkg -s "$1" &> /dev/null
            ;;
        fedora|centos|rhel|almalinux|rocky)
            rpm -q "$1" &> /dev/null
            ;;
        arch|manjaro)
            pacman -Q "$1" &> /dev/null
            ;;
        *)
            # For unsupported distros, assume not installed to force attempt installation
            return 1
            ;;
    esac
}

# Function to check if a service is running and enabled
function is_service_active_and_enabled {
    systemctl is-active --quiet "$1" && systemctl is-enabled --quiet "$1"
}


echo "Starting script execution. Identifying distribution..."

# --- 1. Identify Distribution ---
DISTRO=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    ID_LIKE=$(grep '^ID_LIKE=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    ID=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')

    # Prioritize specific IDs, then ID_LIKE
    if [ -n "$ID" ]; then
        DISTRO=$ID
    elif [ -n "$ID_LIKE" ]; then
        # Pick the first one if multiple are listed
        DISTRO=$(echo $ID_LIKE | awk '{print $1}')
    else
        error_exit "Could not identify Linux distribution. Exiting."
    fi
elif type lsb_release >/dev/null 2>&1; then
    DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]') # Convert to lowercase
elif [ -f /etc/redhat-release ]; then
    DISTRO="rhel" # Generic for RHEL-based
elif [ -f /etc/debian_version ]; then
    DISTRO="debian" # Generic for Debian-based
else
    error_exit "Could not identify Linux distribution. Exiting."
fi

echo "Identified distribution: $DISTRO"

---

## Instalação e Configuração do Cockpit

echo "--- Installing and configuring Cockpit ---"
if ! is_package_installed "cockpit"; then
    echo "Cockpit not found. Installing Cockpit and useful modules (cockpit-machines, cockpit-docker/podman)..."
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
                 echo "Warning: cockpit-podman not found, attempting cockpit-machines only."
                 sudo pacman -Sy --noconfirm cockpit cockpit-machines || error_exit "Failed to install Cockpit and modules."
            fi
            ;;
        *)
            error_exit "Unsupported distribution for Cockpit installation: $DISTRO"
            ;;
    esac
    echo "Cockpit and modules installed."
else
    echo "Cockpit is already installed. Skipping installation."
fi

if ! is_service_active_and_enabled "cockpit.socket"; then
    echo "Cockpit socket not active or enabled. Enabling and starting..."
    sudo systemctl enable --now cockpit.socket || error_exit "Failed to enable/start cockpit.socket."
    echo "Cockpit socket enabled and started."
else
    echo "Cockpit socket is already active and enabled."
fi


echo "Configuring firewall to allow Cockpit access (port 9090)..."
case "$DISTRO" in
    ubuntu|debian|pop|mint)
        if sudo ufw status | grep -q "Status: active"; then
            if ! sudo ufw status | grep -q "9090/tcp ALLOW"; then
                sudo ufw allow 9090/tcp || error_exit "Failed to allow port 9090 in UFW."
                sudo ufw reload # Reload UFW to apply changes
                echo "UFW configured for Cockpit."
            else
                echo "UFW already allows port 9090/tcp."
            fi
        else
            echo "UFW is not active or installed. Skipping UFW configuration. Please configure your firewall manually."
        fi
        ;;
    fedora|centos|rhel|almalinux|rocky)
        if command -v firewall-cmd &> /dev/null; then
            if ! sudo firewall-cmd --query-service=cockpit --zone=public &> /dev/null; then
                sudo firewall-cmd --add-service=cockpit --permanent || error_exit "Failed to add cockpit service to firewalld."
                sudo firewall-cmd --reload || error_exit "Failed to reload firewalld."
                echo "Firewalld configured for Cockpit."
            else
                echo "Firewalld already allows Cockpit service."
            fi
        else
            echo "Firewalld is not active or installed. Skipping firewall configuration. Please configure your firewall manually."
        fi
        ;;
    arch|manjaro)
        if command -v firewall-cmd &> /dev/null; then
            if ! sudo firewall-cmd --query-service=cockpit --zone=public &> /dev/null; then
                sudo firewall-cmd --add-service=cockpit --permanent || error_exit "Failed to add cockpit service to firewalld."
                sudo firewall-cmd --reload || error_exit "Failed to reload firewalld."
                echo "Firewalld configured for Cockpit."
            else
                echo "Firewalld already allows Cockpit service."
            fi
        elif command -v ufw &> /dev/null && sudo ufw status | grep -q "Status: active"; then
            if ! sudo ufw status | grep -q "9090/tcp ALLOW"; then
                sudo ufw allow 9090/tcp || error_exit "Failed to allow port 9090 in UFW."
                sudo ufw reload # Reload UFW to apply changes
                echo "UFW configured for Cockpit."
            else
                echo "UFW already allows port 9090/tcp."
            fi
        else
            echo "No common firewall detected (firewalld/ufw). Skipping firewall configuration. Please configure your firewall manually."
        fi
        ;;
    *)
        echo "Unsupported distribution for automatic firewall configuration. Please configure your firewall manually."
        ;;
esac
echo "Firewall configuration attempted."

echo "Configuring Cockpit session timeout (optional)..."
# Set timeout to 15 minutes (900 seconds)
# This creates/modifies a drop-in file for cockpit.socket
# Check if the directory exists, if not, create it
if [ ! -d "/etc/systemd/system/cockpit.socket.d" ]; then
    sudo mkdir -p /etc/systemd/system/cockpit.socket.d
fi

# Only write if content is different or file doesn't exist
if ! sudo grep -q "IdleTimeoutSec=900" /etc/systemd/system/cockpit.socket.d/timeout.conf 2>/dev/null; then
    echo "[Socket]" | sudo tee /etc/systemd/system/cockpit.socket.d/timeout.conf > /dev/null
    echo "IdleTimeoutSec=900" | sudo tee -a /etc/systemd/system/cockpit.socket.d/timeout.conf > /dev/null
    echo "Cockpit session timeout set to 15 minutes."
    sudo systemctl daemon-reload
    sudo systemctl restart cockpit.socket
else
    echo "Cockpit session timeout already configured."
fi

echo "--- Cockpit Installation and Configuration Complete ---"
echo "You can now access Cockpit via your web browser at: https://$(hostname -I | awk '{print $1}'):9090"
echo "Use your system username and password to log in."
echo ""

---

## Instalação de Outros Pacotes Essenciais

echo "--- Installing other essential packages ---"

# --- 2. Install Dependencies and Common Tools ---
echo "Installing common dependencies and tools..."
case "$DISTRO" in
    ubuntu|debian|pop|mint)
        sudo apt update || error_exit "apt update failed." # Re-run update in case of stale cache
        sudo apt install -y curl wget git vim ca-certificates software-properties-common apt-transport-https || error_exit "Failed to install common dependencies."
        ;;
    fedora|centos|rhel|almalinux|rocky)
        sudo dnf check-update || error_exit "dnf check-update failed." # Re-run update in case of stale cache
        sudo dnf install -y curl wget git vim ca-certificates dnf-plugins-core || error_exit "Failed to install common dependencies."
        ;;
    arch|manjaro)
        sudo pacman -Sy --noconfirm curl wget git vim ca-certificates || error_exit "Failed to install common dependencies."
        ;;
    *)
        error_exit "Unsupported distribution for common dependency installation: $DISTRO"
        ;;
esac
echo "Common dependencies installed."

# --- 3. Install code-server (VS Code in browser) ---
echo "Installing code-server..."
if ! command -v code-server &> /dev/null; then
    curl -fsSL https://code-server.dev/install.sh | sh || error_exit "Failed to install code-server."
    echo "code-server installed. You can run 'code-server' to start it. Access it via http://localhost:8080 (or your server's IP:8080)."
    echo "It will prompt you for a password on first run, which you can find in ~/.config/code-server/config.yaml"
    echo "For multiple users, consider running code-server for each user on a different port or using Docker containers."
    echo "Example for a new user 'devuser':"
    echo "sudo adduser devuser"
    echo "sudo -u devuser code-server --port 8081 --auth password"
else
    echo "code-server is already installed. Skipping installation."
fi

# --- 4. Install Gitea ---
echo "Installing Gitea..."
# Gitea's package name might vary. Checking for the command is more robust.
if ! command -v gitea &> /dev/null; then
    case "$DISTRO" in
        ubuntu|debian|pop|mint)
            # Gitea might be in universe repo, which should be enabled by default on modern Ubuntu/Debian based systems
            if ! is_package_installed "gitea"; then
                sudo apt install -y gitea || error_exit "Failed to install Gitea."
                echo "Gitea installed via apt. You will need to configure it by visiting http://localhost:3000 (or your server's IP:3000) in your browser."
                echo "Refer to the Gitea documentation for proper setup and database configuration."
            else
                echo "Gitea package already installed via apt."
            fi
            ;;
        *)
            echo "Gitea installation via package manager not straightforward for $DISTRO."
            echo "Consider manually downloading the Gitea binary or using Docker for easier management:"
            echo "Download: https://docs.gitea.io/en-us/install-from-binary/"
            echo "Docker: https://docs.gitea.io/en-us/install-with-docker/"
            ;;
    esac
else
    echo "Gitea command already found. Skipping installation."
fi

# --- 5. Install PostgreSQL and phpMyAdmin (configured for PostgreSQL) ---
echo "Installing PostgreSQL and phpMyAdmin..."
if ! is_package_installed "postgresql"; then
    case "$DISTRO" in
        ubuntu|debian|pop|mint)
            sudo apt install -y postgresql postgresql-contrib || error_exit "Failed to install PostgreSQL."
            echo "PostgreSQL installed."
            ;;
        fedora|centos|rhel|almalinux|rocky)
            sudo dnf install -y postgresql-server postgresql-contrib || error_exit "Failed to install PostgreSQL."
            sudo postgresql-setup initdb || error_exit "Failed to initialize PostgreSQL DB."
            echo "PostgreSQL installed."
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm postgresql || error_exit "Failed to install PostgreSQL for Arch."
            if [ ! -d "/var/lib/postgres/data" ]; then
                sudo -u postgres initdb -D /var/lib/postgres/data || error_exit "Failed to initialize PostgreSQL DB for Arch."
            fi
            echo "PostgreSQL installed."
            ;;
        *)
            echo "PostgreSQL installation not straightforward for $DISTRO. Manual installation recommended."
            ;;
    esac
else
    echo "PostgreSQL is already installed. Skipping installation."
fi

if is_package_installed "postgresql"; then # Only proceed with PG service if PG is installed
    if ! is_service_active_and_enabled "postgresql"; then
        case "$DISTRO" in
            ubuntu|debian|pop|mint|fedora|centos|rhel|almalinux|rocky|arch|manjaro)
                sudo systemctl enable --now postgresql || error_exit "Failed to enable/start PostgreSQL."
                echo "PostgreSQL enabled and started."
                ;;
        esac
    else
        echo "PostgreSQL service is already active and enabled."
    fi
fi

# phpMyAdmin installation
echo "Installing Apache/PHP and phpMyAdmin..."
if [ ! -d "/usr/share/phpmyadmin" ] && [ ! -d "/usr/share/webapps/phpmyadmin" ]; then # Check if phpMyAdmin directory exists
    case "$DISTRO" in
        ubuntu|debian|pop|mint)
            sudo apt install -y apache2 php libapache2-mod-php php-cli php-pgsql php-json php-mbstring php-xml php-zip php-gd php-curl || error_exit "Failed to install Apache and PHP dependencies."
            PMA_VERSION="5.2.1" # Check for the latest stable version
            wget -P /tmp https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz || error_exit "Failed to download phpMyAdmin."
            sudo mkdir -p /usr/share/phpmyadmin
            sudo tar -xzf /tmp/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz -C /usr/share/phpmyadmin --strip-components=1 || error_exit "Failed to extract phpMyAdmin."
            sudo rm /tmp/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz
            sudo cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
            sudo sed -i "/\$cfg\['Servers'\]\[\$i\]\['host'\]/a \$cfg['Servers'][\$i]['extension'] = 'pgsql';" /usr/share/phpmyadmin/config.inc.php
            echo "
<Directory /usr/share/phpmyadmin>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    AllowOverride All
</Directory>
Alias /phpmyadmin /usr/share/phpmyadmin
Alias /phpMyAdmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    Require all granted
</Directory>
" | sudo tee /etc/apache2/conf-available/phpmyadmin.conf > /dev/null
            sudo a2enconf phpmyadmin.conf || error_exit "Failed to enable phpMyAdmin Apache config."
            sudo systemctl restart apache2 || error_exit "Failed to restart Apache2."
            echo "phpMyAdmin installed. Access it via http://localhost/phpmyadmin (or your server's IP/phpmyadmin)."
            ;;
        fedora|centos|rhel|almalinux|rocky)
            sudo dnf install -y httpd php php-pgsql php-json php-mbstring php-xml php-zip php-gd php-curl || error_exit "Failed to install httpd and PHP dependencies."
            sudo systemctl enable httpd || error_exit "Failed to enable httpd."
            sudo systemctl start httpd || error_exit "Failed to start httpd."
            PMA_VERSION="5.2.1" # Check for the latest stable version
            wget -P /tmp https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz || error_exit "Failed to download phpMyAdmin."
            sudo mkdir -p /usr/share/phpmyadmin
            sudo tar -xzf /tmp/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz -C /usr/share/phpmyadmin --strip-components=1 || error_exit "Failed to extract phpMyAdmin."
            sudo rm /tmp/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz
            sudo cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
            sudo sed -i "/\$cfg\['Servers'\]\[\$i\]\['host'\]/a \$cfg['Servers'][\$i]['extension'] = 'pgsql';" /usr/share/phpmyadmin/config.inc.php
            echo "
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    AddType application/x-httpd-php .php
    php_flag magic_quotes_gpc Off
    php_flag track_vars On
    php_flag register_globals Off
    php_admin_flag allow_url_fopen Off
    php_value include_path .
    php_admin_value upload_max_filesize 8M
    php_admin_value post_max_size 8M
    php_admin_value max_execution_time 360
    php_admin_value max_input_time 360
    AllowOverride All
    Require all granted
</Directory>
" | sudo tee /etc/httpd/conf.d/phpmyadmin.conf > /dev/null
            sudo systemctl restart httpd || error_exit "Failed to restart httpd."
            echo "phpMyAdmin installed. Access it via http://localhost/phpmyadmin (or your server's IP/phpmyadmin)."
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm apache php php-apache php-pgsql || error_exit "Failed to install Apache/PHP for Arch."
            sudo systemctl enable --now httpd.service || error_exit "Failed to enable/start Apache."
            PMA_VERSION="5.2.1" # Check for the latest stable version
            wget -P /tmp https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz || error_exit "Failed to download phpMyAdmin."
            sudo mkdir -p /usr/share/webapps/phpmyadmin
            sudo tar -xzf /tmp/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz -C /usr/share/webapps/phpmyadmin --strip-components=1 || error_exit "Failed to extract phpMyAdmin."
            sudo rm /tmp/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz
            sudo cp /usr/share/webapps/phpmyadmin/config.sample.inc.php /usr/share/webapps/phpmyadmin/config.inc.php
            sudo sed -i "/\$cfg\['Servers'\]\[\$i\]\['host'\]/a \$cfg['Servers'][\$i]['extension'] = 'pgsql';" /usr/share/webapps/phpmyadmin/config.inc.php
            echo "IncludeOptional conf/extra/phpmyadmin.conf" | sudo tee -a /etc/httpd/conf/httpd.conf > /dev/null
            echo "
Alias /phpmyadmin \"/usr/share/webapps/phpmyadmin\"
<Directory \"/usr/share/webapps/phpmyadmin\">
    DirectoryIndex index.php
    AllowOverride All
    Options FollowSymlinks
    Require all granted
</Directory>
" | sudo tee /etc/httpd/conf/extra/phpmyadmin.conf > /dev/null
            sudo systemctl restart httpd.service || error_exit "Failed to restart Apache for Arch."
            echo "phpMyAdmin installed. Access it via http://localhost/phpmyadmin (or your server's IP/phpmyadmin)."
            ;;
        *)
            echo "phpMyAdmin installation not straightforward for $DISTRO. Manual installation recommended."
            ;;
    esac
    echo "Remember to secure your phpMyAdmin installation and configure the 'blowfish_secret' in /usr/share/phpmyadmin/config.inc.php (or /usr/share/webapps/phpmyadmin/config.inc.php on Arch)."
    echo "You will also need to create a PostgreSQL user and database for phpMyAdmin to connect to."
    echo "Example for PostgreSQL user (run as postgres user): sudo -u postgres psql -c \"CREATE USER myuser WITH PASSWORD 'mypassword';\""
    echo "And then grant privileges: sudo -u postgres psql -c \"ALTER USER myuser WITH SUPERUSER;\" (for simplicity, but consider more granular permissions)"
    echo "Then edit your phpMyAdmin config to add your PostgreSQL server details."
else
    echo "phpMyAdmin appears to be already installed. Skipping installation."
fi

# --- 6. SSH User and Session Management (Command-line Tools) ---
echo "--- SSH User and Session Management ---"
echo "To manage SSH users, you directly manage system users. You can also use Cockpit's 'Accounts' section."
echo "Add a new user for SSH access:"
echo "  sudo adduser <username>"
echo "  sudo usermod -aG sudo <username> # (Optional: grant sudo privileges)"
echo "  sudo mkdir -p /home/<username>/.ssh"
echo "  # Copy your public key or create a new one:"
echo "  # sudo cp ~/.ssh/authorized_keys /home/<username>/.ssh/"
echo "  # sudo chown -R <username>:<username> /home/<username>/.ssh"
echo "  # sudo chmod 700 /home/<username>/.ssh"
echo "  # sudo chmod 600 /home/<username>/.ssh/authorized_keys"

echo "To remove a user:"
echo "  sudo deluser --remove-home <username>"

echo "To see active SSH sessions:"
echo "  who"
echo "  w"
echo "  sudo ss -tnp | grep ':22' # For listening SSH daemon and connected clients"
echo "  sudo ps aux | grep 'sshd:' # Look for active sshd processes for specific users"

# --- 7. code-server Login and Session Management (Command-line Tools) ---
echo "--- code-server Login and Session Management ---"
echo "For code-server, each user ideally runs their own instance on a dedicated port or in a container."
echo "To create a new code-server user (system user) and run code-server for them:"
echo "  1. Create system user: sudo adduser newcodeuser"
echo "  2. Switch to user: sudo -i -u newcodeuser"
echo "  3. Install code-server for this user (if not already installed system-wide):"
echo "     curl -fsSL https://code-server.dev/install.sh | sh"
echo "  4. Start code-server on a unique port (e.g., 8081, 8082):"
echo "     code-server --port 8081 --auth password"
echo "     (The password will be in ~/.config/code-server/config.yaml of newcodeuser)"
echo "  5. To run in background (use systemd service for production, which you can manage via Cockpit):"
echo "     nohup code-server --port 8081 --auth password &"
echo "  6. Log out from user: exit"
echo "Consider creating Systemd services for each code-server instance, which can then be monitored and managed directly from Cockpit under 'Services'."

echo "To check if code-server instances are running (and by whom):"
echo "  ps aux | grep code-server"
echo "Look for 'code-server --port <port_number>' and the associated user."

echo "To terminate a code-server session (by PID or killing user processes):"
echo "  sudo pkill -u <username> code-server # Kills all code-server processes for that user"
echo "  # Or find PID: ps aux | grep 'code-server --port 8081' | grep -v grep | awk '{print \$2}'"
echo "  # Then kill: sudo kill <PID>"

echo "--- Script Finished ---"
echo "Please review the output above for any errors or manual steps required."
echo ""
echo "--- Important Security Considerations ---"
echo "1. Use strong, unique passwords for your system users."
echo "2. Keep your system updated regularly: 'sudo apt update && sudo apt upgrade' or 'sudo dnf update' or 'sudo pacman -Syu'."
echo "3. Consider setting up Two-Factor Authentication (2FA) for SSH and potentially Cockpit if available."
echo "4. Restrict SSH access to specific IPs (if possible) in /etc/ssh/sshd_config."
echo "5. For production environments, consider using a reverse proxy (like Nginx or Apache) with TLS/SSL for Cockpit access,"
echo "   though Cockpit provides its own self-signed certificate by default."
echo "6. Only install modules you actually need in Cockpit."
echo "7. Regularly review logs (accessible via Cockpit) for suspicious activity."
echo "---------------------------------------"
echo "Good luck!"
