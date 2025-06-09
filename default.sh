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

echo "Starting script execution. Identifying distribution..."

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

---

## Instalação e Configuração do Cockpit

echo "--- Installing and configuring Cockpit ---"
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

echo "Enabling and starting Cockpit socket..."
sudo systemctl enable --now cockpit.socket || error_exit "Failed to enable/start cockpit.socket."
echo "Cockpit socket enabled and started."

echo "Configuring firewall to allow Cockpit access (port 9090)..."
case "$DISTRO" in
    ubuntu|debian|pop|mint)
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

echo "Configuring Cockpit session timeout (optional)..."
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

---

## Instalação de Outros Pacotes Essenciais

echo "--- Installing other essential packages ---"

# --- 2. Install Dependencies and Common Tools ---
echo "Installing common dependencies and tools..."
case "$DISTRO" in
    ubuntu|debian|pop|mint)
        # apt update already done for cockpit
        sudo apt install -y curl wget git vim ca-certificates software-properties-common apt-transport-https || error_exit "Failed to install common dependencies."
        ;;
    fedora|centos|rhel|almalinux|rocky)
        # dnf check-update already done for cockpit
        sudo dnf install -y curl wget git vim ca-certificates dnf-plugins-core || error_exit "Failed to install common dependencies."
        ;;
    arch|manjaro)
        # pacman -Sy already done for cockpit
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
    echo "code-server is already installed."
fi

# --- 4. Install Gitea ---
echo "Installing Gitea..."
if ! command -v gitea &> /dev/null; then
    case "$DISTRO" in
        ubuntu|debian|pop|mint)
            sudo apt install -y gitea || error_exit "Failed to install Gitea."
            echo "Gitea installed via apt. You will need to configure it by visiting http://localhost:3000 (or your server's IP:3000) in your browser."
            echo "Refer to the Gitea documentation for proper setup and database configuration."
            ;;
        *)
            echo "Gitea installation via package manager not straightforward for $DISTRO."
            echo "Consider manually downloading the Gitea binary or using Docker for easier management:"
            echo "Download: https://docs.gitea.io/en-us/install-from-binary/"
            echo "Docker: https://docs.gitea.io/en-us/install-with-docker/"
            ;;
    esac
else
    echo "Gitea is already installed."
fi

# --- 5. Install PostgreSQL and phpMyAdmin (configured for PostgreSQL) ---
echo "Installing PostgreSQL and phpMyAdmin..."
case "$DISTRO" in
    ubuntu|debian|pop|mint)
        sudo apt install -y postgresql postgresql-contrib || error_exit "Failed to install PostgreSQL."
        echo "PostgreSQL installed."

        sudo apt install -y apache2 php libapache2-mod-php php-cli php-pgsql php-json php-mbstring php-xml php-zip php-gd php-curl || error_exit "Failed to install Apache and PHP dependencies."

        if [ ! -d "/usr/share/phpmyadmin" ]; then
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
            echo "Remember to secure your phpMyAdmin installation and configure the 'blowfish_secret' in /usr/share/phpmyadmin/config.inc.php"
            echo "You will also need to create a PostgreSQL user and database for phpMyAdmin to connect to."
            echo "Example for PostgreSQL user (run as postgres user): sudo -u postgres psql -c \"CREATE USER myuser WITH PASSWORD 'mypassword';\""
            echo "And then grant privileges: sudo -u postgres psql -c \"ALTER USER myuser WITH SUPERUSER;\" (for simplicity, but consider more granular permissions)"
            echo "Then edit /usr/share/phpmyadmin/config.inc.php to add your PostgreSQL server details."
        else
            echo "phpMyAdmin is already installed."
        fi
        ;;
    fedora|centos|rhel|almalinux|rocky)
        sudo dnf install -y postgresql-server postgresql-contrib || error_exit "Failed to install PostgreSQL."
        sudo postgresql-setup initdb || error_exit "Failed to initialize PostgreSQL DB."
        sudo systemctl enable postgresql || error_exit "Failed to enable PostgreSQL."
        sudo systemctl start postgresql || error_exit "Failed to start PostgreSQL."
        echo "PostgreSQL installed and started."

        sudo dnf install -y httpd php php-pgsql php-json php-mbstring php-xml php-zip php-gd php-curl || error_exit "Failed to install httpd and PHP dependencies."
        sudo systemctl enable httpd || error_exit "Failed to enable httpd."
        sudo systemctl start httpd || error_exit "Failed to start httpd."

        if [ ! -d "/usr/share/phpmyadmin" ]; then
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
            echo "Remember to secure your phpMyAdmin installation and configure the 'blowfish_secret' in /usr/share/phpmyadmin/config.inc.php"
            echo "You will also need to create a PostgreSQL user and database for phpMyAdmin to connect to."
            echo "Example for PostgreSQL user (run as postgres user): sudo -u postgres psql -c \"CREATE USER myuser WITH PASSWORD 'mypassword';\""
            echo "And then grant privileges: sudo -u postgres psql -c \"ALTER USER myuser WITH SUPERUSER;\" (for simplicity, but consider more granular permissions)"
            echo "Then edit /usr/share/phpmyadmin/config.inc.php to add your PostgreSQL server details."
        else
            echo "phpMyAdmin is already installed."
        fi
        ;;
    arch|manjaro)
        sudo pacman -Sy --noconfirm postgresql php php-apache php-pgsql || error_exit "Failed to install PostgreSQL and PHP for Arch."
        sudo systemctl enable --now postgresql.service || error_exit "Failed to enable/start PostgreSQL."
        echo "PostgreSQL installed and started."

        if [ ! -d "/var/lib/postgres/data" ]; then
            sudo -u postgres initdb -D /var/lib/postgres/data || error_exit "Failed to initialize PostgreSQL DB for Arch."
        fi

        sudo pacman -Sy --noconfirm apache || error_exit "Failed to install Apache for Arch."
        sudo systemctl enable --now httpd.service || error_exit "Failed to enable/start Apache."

        if [ ! -d "/usr/share/webapps/phpmyadmin" ]; then
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
            echo "Remember to secure your phpMyAdmin installation and configure the 'blowfish_secret' in /usr/share/webapps/phpmyadmin/config.inc.php"
            echo "You will also need to create a PostgreSQL user and database for phpMyAdmin to connect to."
            echo "Example for PostgreSQL user (run as postgres user): sudo -u postgres psql -c \"CREATE USER myuser WITH PASSWORD 'mypassword';\""
            echo "And then grant privileges: sudo -u postgres psql -c \"ALTER USER myuser WITH SUPERUSER;\" (for simplicity, but consider more granular permissions)"
            echo "Then edit /usr/share/phpmyadmin/config.inc.php to add your PostgreSQL server details."
        else
            echo "phpMyAdmin is already installed."
        fi
        ;;
    *)
        echo "PostgreSQL and phpMyAdmin installation not straightforward for $DISTRO. Manual installation recommended."
        ;;
esac

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
