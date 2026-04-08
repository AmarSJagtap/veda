#!/bin/bash
# ──────────────────────────────────────────────
# Voice Bot Widget — EC2 Deployment Script
# Run this on a fresh Ubuntu 22.04 / 24.04 EC2
# Usage: chmod +x deploy.sh && ./deploy.sh
# ──────────────────────────────────────────────

set -e

APP_NAME="voice-bot-widget"
REPO_URL="https://github.com/AmarJagtap-BTS/Voice_widget.git"
APP_DIR="/home/ubuntu/$APP_NAME"
NODE_VERSION="20"

echo "═══════════════════════════════════════"
echo "  Voice Bot Widget — EC2 Deployment"
echo "═══════════════════════════════════════"

# ── 1. System update ──
echo "▸ Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# ── 2. Install Node.js (via NodeSource) ──
echo "▸ Installing Node.js $NODE_VERSION..."
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
sudo apt install -y nodejs

echo "  Node: $(node -v)  |  npm: $(npm -v)"

# ── 3. Install build tools (needed for better-sqlite3) ──
echo "▸ Installing build essentials..."
sudo apt install -y build-essential python3 git

# ── 4. Install PM2 globally ──
echo "▸ Installing PM2..."
sudo npm install -g pm2

# ── 5. Install Nginx ──
echo "▸ Installing Nginx..."
sudo apt install -y nginx

# ── 6. Clone the repository ──
echo "▸ Cloning repository..."
if [ -d "$APP_DIR" ]; then
    echo "  Directory exists, pulling latest..."
    cd "$APP_DIR" && git pull origin main
else
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
fi

# ── 7. Install dependencies ──
echo "▸ Installing Node.js dependencies..."
cd "$APP_DIR"
npm install --production

# ── 8. Setup environment file ──
if [ ! -f "$APP_DIR/.env" ]; then
    echo "▸ Creating .env from example..."
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    echo ""
    echo "  ⚠️  IMPORTANT: Edit your .env file with real API keys!"
    echo "  Run: nano $APP_DIR/.env"
    echo ""
fi

# ── 9. Setup Nginx reverse proxy ──
echo "▸ Configuring Nginx..."
sudo tee /etc/nginx/sites-available/$APP_NAME > /dev/null <<'NGINX'
server {
    listen 80;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://127.0.0.1:3800;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }

    # Increase body size for file uploads
    client_max_body_size 50M;
}
NGINX

sudo ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

# ── 10. Start the app with PM2 ──
echo "▸ Starting application with PM2..."
cd "$APP_DIR"
pm2 delete $APP_NAME 2>/dev/null || true
pm2 start ecosystem.config.js
pm2 save
pm2 startup systemd -u ubuntu --hp /home/ubuntu | tail -1 | sudo bash

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ Deployment Complete!"
echo "═══════════════════════════════════════════════"
echo ""
echo "  App URL  : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo '<YOUR_EC2_PUBLIC_IP>')"
echo "  App Dir  : $APP_DIR"
echo "  Logs     : pm2 logs $APP_NAME"
echo "  Status   : pm2 status"
echo "  Restart  : pm2 restart $APP_NAME"
echo ""
echo "  📝 Next steps:"
echo "  1. Edit .env:  nano $APP_DIR/.env"
echo "  2. Restart:    pm2 restart $APP_NAME"
echo "  3. (Optional)  Setup SSL with: sudo certbot --nginx"
echo "═══════════════════════════════════════════════"
