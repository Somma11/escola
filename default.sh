#!/bin/bash

# Function to check and install package manager
install_package_manager() {
    local manager=$1
    if ! command -v "$manager" &> /dev/null; then
        echo "$manager não está instalado. Instalando..."
        
        # Detect package manager and install accordingly
        if command -v apt &> /dev/null; then
            sudo apt update
            sudo apt install -y "$manager"
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y "$manager"
        elif command -v yum &> /dev/null; then
            sudo yum install -y "$manager"
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --noconfirm "$manager"
        else
            echo "Distribuição não suportada. Instale $manager manualmente."
            exit 1
        fi
    else
        echo "$manager já está instalado."
    fi
}

# Function to install Flatpak
install_flatpak() {
    install_package_manager flatpak
    
    # Add Flathub repository
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

# Function to install Snap
install_snap() {
    install_package_manager snapd
    
    # Enable and start snapd service
    sudo systemctl enable --now snapd.socket
}

# Function to install Android Studio via Flatpak
install_android_studio() {
    if ! flatpak list | grep -q "com.google.AndroidStudio"; then
        echo "Instalando Android Studio via Flatpak..."
        flatpak install --system -y flathub com.google.AndroidStudio
    else
        echo "Android Studio já está instalado."
    fi
}

# Function to install MySQL Workbench via Snap
install_mysql_workbench() {
    if ! snap list | grep -q "mysql-workbench-community"; then
        echo "Instalando MySQL Workbench via Snap..."
        sudo snap install mysql-workbench-community
    else
        echo "MySQL Workbench já está instalado."
    fi
}

# Main script
main() {
    # Check and install Flatpak
    install_flatpak

    # Install Android Studio via Flatpak
    install_android_studio

    # Check and install Snap
    install_snap

    # Install MySQL Workbench via Snap
    install_mysql_workbench

    echo "Instalação concluída!"
}

# Run the main function
main
