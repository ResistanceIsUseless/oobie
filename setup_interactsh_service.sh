#!/bin/bash

# Interactsh Service Setup Script
# Creates systemd services for interactsh-server and interactsh-client with notify

set -e

# Configuration
DOMAIN="XXXXXXXXXXXXXXXX" # Replace with your domain
PUBLIC_IP=""
HTTP_DIR="/var/www/html"
HTTP_INDEX="${HTTP_DIR}/index.html"
TOKEN="XXXXXXXXXXXXXXX"
SERVICE_USER="interactsh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get public IP automatically
echo -e "${YELLOW}Getting public IP address...${NC}"
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me)

if [ -z "$PUBLIC_IP" ]; then
    echo -e "${RED}Failed to get public IP address${NC}"
    exit 1
fi

echo -e "${GREEN}Public IP: $PUBLIC_IP${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root or with sudo${NC}"
    exit 1
fi

# Check and copy interactsh binaries
echo -e "${YELLOW}Checking for interactsh binaries...${NC}"

# Determine the actual user's home directory (even when using sudo)
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

GOBIN_PATH="$USER_HOME/go/bin"

# Check if interactsh-server exists
INTERACTSH_SERVER_PATH=""
if [ -f "$GOBIN_PATH/interactsh-server" ]; then
    INTERACTSH_SERVER_PATH="$GOBIN_PATH/interactsh-server"
elif command -v interactsh-server &> /dev/null; then
    INTERACTSH_SERVER_PATH=$(which interactsh-server)
fi

if [ -n "$INTERACTSH_SERVER_PATH" ]; then
    echo -e "${GREEN}Found interactsh-server at: $INTERACTSH_SERVER_PATH${NC}"
    
    # Stop any running instances
    echo -e "${YELLOW}Stopping any running interactsh services...${NC}"
    systemctl stop interactsh-server.service 2>/dev/null || true
    systemctl stop interactsh-server-debug.service 2>/dev/null || true
    pkill -f interactsh-server 2>/dev/null || true
    sleep 2
    
    # Remove old binary if exists
    if [ -f "/usr/local/bin/interactsh-server" ]; then
        rm -f /usr/local/bin/interactsh-server
    fi
    
    # Copy with install command to handle busy files
    install -m 755 "$INTERACTSH_SERVER_PATH" /usr/local/bin/interactsh-server
    
    # Verify the copy was successful
    if [ -f "/usr/local/bin/interactsh-server" ]; then
        echo -e "${GREEN}Successfully copied interactsh-server to /usr/local/bin/${NC}"
        ls -la /usr/local/bin/interactsh-server
    else
        echo -e "${RED}Failed to copy interactsh-server to /usr/local/bin/${NC}"
        exit 1
    fi
else
    echo -e "${RED}interactsh-server not found in PATH or $GOBIN_PATH${NC}"
    echo -e "${YELLOW}Please install it with: go install -v github.com/projectdiscovery/interactsh/cmd/interactsh-server@latest${NC}"
    exit 1
fi

# Check if interactsh-client exists
INTERACTSH_CLIENT_PATH=""
if [ -f "$GOBIN_PATH/interactsh-client" ]; then
    INTERACTSH_CLIENT_PATH="$GOBIN_PATH/interactsh-client"
elif command -v interactsh-client &> /dev/null; then
    INTERACTSH_CLIENT_PATH=$(which interactsh-client)
fi

if [ -n "$INTERACTSH_CLIENT_PATH" ]; then
    echo -e "${GREEN}Found interactsh-client at: $INTERACTSH_CLIENT_PATH${NC}"
    
    # Stop any running client instances
    systemctl stop interactsh-client.service 2>/dev/null || true
    pkill -f interactsh-client 2>/dev/null || true
    
    # Remove old binary if exists
    if [ -f "/usr/local/bin/interactsh-client" ]; then
        rm -f /usr/local/bin/interactsh-client
    fi
    
    # Copy with install command
    install -m 755 "$INTERACTSH_CLIENT_PATH" /usr/local/bin/interactsh-client
    
    # Verify the copy was successful
    if [ -f "/usr/local/bin/interactsh-client" ]; then
        echo -e "${GREEN}Successfully copied interactsh-client to /usr/local/bin/${NC}"
        ls -la /usr/local/bin/interactsh-client
    else
        echo -e "${RED}Failed to copy interactsh-client to /usr/local/bin/${NC}"
        exit 1
    fi
else
    echo -e "${RED}interactsh-client not found in PATH or $GOBIN_PATH${NC}"
    echo -e "${YELLOW}Please install it with: go install -v github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest${NC}"
    exit 1
fi

# Check if notify exists (optional, but warn if missing)
if [ -f "$GOBIN_PATH/notify" ]; then
    echo -e "${GREEN}Found notify in $GOBIN_PATH${NC}"
    cp "$GOBIN_PATH/notify" /usr/local/bin/
    chmod +x /usr/local/bin/notify
elif ! command -v notify &> /dev/null; then
    echo -e "${YELLOW}Warning: notify not found. Discord notifications will not work.${NC}"
    echo -e "${YELLOW}Install it with: go install -v github.com/projectdiscovery/notify/cmd/notify@latest${NC}"
    echo -e "${YELLOW}And configure it with: notify -provider-config${NC}"
fi

# Check for notify configuration
NOTIFY_CONFIG="$USER_HOME/.config/notify/provider-config.yaml"
if [ -f "$NOTIFY_CONFIG" ]; then
    echo -e "${GREEN}Found notify configuration at $NOTIFY_CONFIG${NC}"
    
    # Check if Discord is configured
    if grep -q "discord:" "$NOTIFY_CONFIG" && grep -q "discord_webhook_url:" "$NOTIFY_CONFIG"; then
        echo -e "${GREEN}Discord provider is configured${NC}"
        
        # Copy notify config for service user
        mkdir -p /home/$SERVICE_USER/.config/notify
        cp "$NOTIFY_CONFIG" /home/$SERVICE_USER/.config/notify/
        chown -R $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER/.config
        
        # Display Discord configuration details
        DISCORD_CHANNEL=$(grep -A5 "discord:" "$NOTIFY_CONFIG" | grep "discord_channel:" | awk -F'"' '{print $2}')
        DISCORD_USERNAME=$(grep -A5 "discord:" "$NOTIFY_CONFIG" | grep "discord_username:" | awk -F'"' '{print $2}')
        
        if [ -n "$DISCORD_CHANNEL" ]; then
            echo -e "${GREEN}  Channel: $DISCORD_CHANNEL${NC}"
        fi
        if [ -n "$DISCORD_USERNAME" ]; then
            echo -e "${GREEN}  Username: $DISCORD_USERNAME${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: Discord provider not configured in $NOTIFY_CONFIG${NC}"
        echo -e "${YELLOW}Configure it with: notify -provider-config${NC}"
    fi
else
    echo -e "${YELLOW}Warning: notify configuration not found at $NOTIFY_CONFIG${NC}"
    echo -e "${YELLOW}Discord notifications will not work until configured.${NC}"
    echo -e "${YELLOW}Configure it with: notify -provider-config${NC}"
fi

# Create service user if doesn't exist
if ! id "$SERVICE_USER" &>/dev/null; then
    echo -e "${YELLOW}Creating service user: $SERVICE_USER${NC}"
    useradd -r -s /bin/false -m $SERVICE_USER
fi

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p /etc/interactsh
mkdir -p /var/log/interactsh
mkdir -p $HTTP_DIR

# Create default index.html if doesn't exist
if [ ! -f "$HTTP_INDEX" ]; then
    echo -e "${YELLOW}Creating default index.html...${NC}"
    cat > "$HTTP_INDEX" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Interactsh Server</title>
</head>
<body>
    <h1>Interactsh OOB Server</h1>
    <p>Out-of-Band interaction server is running.</p>
</body>
</html>
EOF
    chown $SERVICE_USER:$SERVICE_USER "$HTTP_INDEX"
fi

# Set permissions
chown -R $SERVICE_USER:$SERVICE_USER /var/log/interactsh
chown -R $SERVICE_USER:$SERVICE_USER $HTTP_DIR

# Ensure service user home directory has proper permissions
echo -e "${YELLOW}Setting up service user home directory...${NC}"
if [ ! -d "/home/$SERVICE_USER" ]; then
    echo -e "${YELLOW}Home directory doesn't exist, creating it...${NC}"
    mkdir -p /home/$SERVICE_USER
fi

# Create all necessary directories
mkdir -p /home/$SERVICE_USER/.local/share
mkdir -p /home/$SERVICE_USER/.config/interactsh-client
mkdir -p /home/$SERVICE_USER/.config/notify

# Create a minimal interactsh-client config file
echo -e "${YELLOW}Creating interactsh-client config...${NC}"
cat > /home/$SERVICE_USER/.config/interactsh-client/config.yaml << EOF
# Minimal interactsh-client config
# This file just needs to exist
EOF

# Copy notify config if it exists
if [ -f "$NOTIFY_CONFIG" ]; then
    echo -e "${YELLOW}Copying notify configuration...${NC}"
    cp "$NOTIFY_CONFIG" /home/$SERVICE_USER/.config/notify/provider-config.yaml
    chmod 644 /home/$SERVICE_USER/.config/notify/provider-config.yaml
    echo -e "${GREEN}Notify config copied successfully${NC}"
else
    echo -e "${YELLOW}Warning: Notify config not found, Discord notifications may not work${NC}"
fi

# Set ownership and permissions
echo -e "${YELLOW}Setting ownership and permissions...${NC}"
chown -R $SERVICE_USER:$SERVICE_USER /home/$SERVICE_USER
chmod 755 /home/$SERVICE_USER
chmod -R 755 /home/$SERVICE_USER/.local
chmod -R 755 /home/$SERVICE_USER/.config
chmod 644 /home/$SERVICE_USER/.config/interactsh-client/config.yaml

# Create interactsh-server systemd service
echo -e "${YELLOW}Creating interactsh-server service...${NC}"
cat > /etc/systemd/system/interactsh-server.service << EOF
[Unit]
Description=Interactsh Server
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=/home/$SERVICE_USER
Environment="HOME=/home/$SERVICE_USER"
Environment="USER=$SERVICE_USER"
ExecStart=/usr/local/bin/interactsh-server \\
    -d $DOMAIN \\
    -http-index $HTTP_INDEX \\
    -http-directory $HTTP_DIR \\
    -wildcard \\
    -ip $PUBLIC_IP \\
    -lip 0.0.0.0 \\
    -t $TOKEN
Restart=always
RestartSec=10
StandardOutput=append:/var/log/interactsh/server.log
StandardError=append:/var/log/interactsh/server.log

# Security hardening (relaxed for interactsh)
NoNewPrivileges=true
PrivateTmp=false
ProtectSystem=false
ProtectHome=false
ReadWritePaths=/var/log/interactsh /var/www/html /home/$SERVICE_USER

# Allow binding to privileged ports
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Create interactsh-client systemd service
echo -e "${YELLOW}Creating interactsh-client service...${NC}"
cat > /etc/systemd/system/interactsh-client.service << EOF
[Unit]
Description=Interactsh Client with Discord Notifications
After=network.target interactsh-server.service
Requires=interactsh-server.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=/home/$SERVICE_USER
Environment="HOME=/home/$SERVICE_USER"
Environment="USER=$SERVICE_USER"
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash -c 'cd /home/$SERVICE_USER && /usr/local/bin/interactsh-client -s $DOMAIN -t $TOKEN | /usr/local/bin/notify -provider discord'
Restart=always
RestartSec=10
StandardOutput=append:/var/log/interactsh/client.log
StandardError=append:/var/log/interactsh/client.log

# Relaxed security for interactsh-client
NoNewPrivileges=false
PrivateTmp=false
ProtectSystem=false
ProtectHome=false
ReadWritePaths=/var/log/interactsh /home/$SERVICE_USER

[Install]
WantedBy=multi-user.target
EOF

# Create configuration file
echo -e "${YELLOW}Creating configuration file...${NC}"
cat > /etc/interactsh/config.env << EOF
# Interactsh Configuration
DOMAIN=$DOMAIN
PUBLIC_IP=$PUBLIC_IP
HTTP_DIR=$HTTP_DIR
HTTP_INDEX=$HTTP_INDEX
TOKEN=$TOKEN
SERVICE_USER=$SERVICE_USER
EOF

# Create log rotation config
echo -e "${YELLOW}Setting up log rotation...${NC}"
cat > /etc/logrotate.d/interactsh << EOF
/var/log/interactsh/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 $SERVICE_USER $SERVICE_USER
    sharedscripts
    postrotate
        systemctl reload interactsh-server.service > /dev/null 2>&1 || true
        systemctl reload interactsh-client.service > /dev/null 2>&1 || true
    endscript
}
EOF

# Create update script for IP changes
echo -e "${YELLOW}Creating IP update script...${NC}"
cat > /usr/local/bin/update-interactsh-ip.sh << 'EOF'
#!/bin/bash
# Update Interactsh server IP

source /etc/interactsh/config.env

NEW_IP=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com)
OLD_IP=$PUBLIC_IP

if [ "$NEW_IP" != "$OLD_IP" ] && [ -n "$NEW_IP" ]; then
    echo "IP changed from $OLD_IP to $NEW_IP"
    sed -i "s/PUBLIC_IP=.*/PUBLIC_IP=$NEW_IP/" /etc/interactsh/config.env
    sed -i "s/-ip [0-9.]*/-ip $NEW_IP/" /etc/systemd/system/interactsh-server.service
    systemctl daemon-reload
    systemctl restart interactsh-server.service
    systemctl restart interactsh-client.service
    echo "Services restarted with new IP: $NEW_IP"
else
    echo "IP unchanged: $OLD_IP"
fi
EOF

chmod +x /usr/local/bin/update-interactsh-ip.sh

# Create cron job for IP updates
echo -e "${YELLOW}Setting up IP update cron job...${NC}"
cat > /etc/cron.d/interactsh-ip-update << EOF
# Check for IP changes every 5 minutes
*/5 * * * * root /usr/local/bin/update-interactsh-ip.sh >> /var/log/interactsh/ip-update.log 2>&
EOF

# Reload systemd
echo -e "${YELLOW}Reloading systemd...${NC}"
systemctl daemon-reload

# Enable services
echo -e "${YELLOW}Enabling services...${NC}"
systemctl enable interactsh-server.service
systemctl enable interactsh-client.service

# Start services
echo -e "${YELLOW}Starting services...${NC}"
systemctl start interactsh-server.service
sleep 5
systemctl start interactsh-client.service

# Check status
echo -e "${GREEN}Checking service status...${NC}"
systemctl status interactsh-server.service --no-pager
echo ""
systemctl status interactsh-client.service --no-pager

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${YELLOW}Configuration saved to: /etc/interactsh/config.env${NC}"
echo -e "${YELLOW}Logs location: /var/log/interactsh/${NC}"
echo ""
echo -e "${GREEN}Useful commands:${NC}"
echo "  systemctl status interactsh-server"
echo "  systemctl status interactsh-client"
echo "  journalctl -u interactsh-server -f"
echo "  journalctl -u interactsh-client -f"
echo "  tail -f /var/log/interactsh/server.log"
echo "  tail -f /var/log/interactsh/client.log"
echo "  /usr/local/bin/update-interactsh-ip.sh"