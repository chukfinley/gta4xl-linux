#!/bin/bash
# T3 Code as a service on the tablet, as a browser app on the desktop.
cat > /etc/systemd/system/t3code.service <<'UNIT'
[Unit]
Description=T3 Code
After=network-online.target

[Service]
User=user
Environment=HOME=/home/user PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/t3 serve --host 127.0.0.1 --port 3773 --base-dir /home/user/.t3
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now t3code
cat > /usr/share/applications/t3code.desktop <<'APP'
[Desktop Entry]
Name=T3 Code
Exec=brave-browser --app=http://127.0.0.1:3773
Icon=utilities-terminal
Type=Application
Categories=Development;
APP
