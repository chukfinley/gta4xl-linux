#!/bin/bash
# Standard apps on the tablet, no GNOME Keyring. Light apps only.
export DEBIAN_FRONTEND=noninteractive
apt-get purge -y -qq gnome-keyring gnome-keyring-pkcs11 libpam-gnome-keyring seahorse 2>&1 | tail -1
rm -rf /home/user/.local/share/keyrings
apt-get install -y -qq --no-install-recommends \
  gnome-calendar gnome-contacts gnome-characters gnome-logs baobab simple-scan- \
  gnome-text-editor gnome-sound-recorder gnome-maps snapshot- \
  flatpak gnome-software- xdg-desktop-portal-gtk \
  wget git jq ripgrep fd-find btop neovim ncdu tree zip p7zip-full \
  openssh-client net-tools dnsutils traceroute mtr-tiny \
  fonts-jetbrains-mono fonts-liberation libsecret-tools- \
  python3-pip pipx golang-go- \
  thunderbird- cheese- 2>&1 | tail -1
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Official ARM64 packages
cd /var/tmp
curl -fsSLO "https://github.com/rustdesk/rustdesk/releases/download/1.5.0/rustdesk-1.5.0-aarch64.deb"
curl -fsSL https://api.github.com/repos/mattermost/desktop/releases/latest | jq -r ".assets[].browser_download_url" | grep -E "_arm64\.deb$" | head -1 | xargs -r curl -fsSLO
apt-get install -y -qq --no-install-recommends ./rustdesk*.deb ./mattermost*.deb 2>&1 | tail -1
rm -f rustdesk*.deb mattermost*.deb

# Web apps for services without an ARM64 build
webapp() {
  cat > "/usr/share/applications/web-$1.desktop" <<APP
[Desktop Entry]
Name=$2
Exec=brave-browser --app=$3
Icon=$4
Type=Application
Categories=Network;
APP
}
webapp spotify "Spotify" https://open.spotify.com audio-headphones
webapp bitwarden "Bitwarden" https://vault.bitwarden.com dialog-password
webapp t3chat "T3 Chat" https://t3.chat user-available
webapp claude "Claude" https://claude.ai user-available
webapp youtube "YouTube" https://www.youtube.com video-display
update-desktop-database -q

# Electron and Chromium apps store secrets in a plain file without a keyring
grep -q password-store /home/user/.config/brave-flags.conf || echo '--password-store=basic' >> /home/user/.config/brave-flags.conf
chown user:user /home/user/.config/brave-flags.conf
sed -i 's#--no-sandbox #--no-sandbox --password-store=basic #' /usr/share/applications/t3code.desktop
systemctl --global mask gcr-ssh-agent.socket gcr-ssh-agent.service 2>/dev/null
echo APPS-DONE
