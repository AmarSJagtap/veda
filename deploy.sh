#!/bin/bash
# ──────────────────────────────────────────────
# Voice Bot Widget — EC2 Deployment Script
# Run this on a fresh Ubuntu 22.04 / 24.04 EC2
# Usage:
#   chmod +x deploy.sh && ./deploy.sh
#
# Re-run at any time to pull latest code & restart.
# ──────────────────────────────────────────────

set -e

APP_NAME="voice-bot-widget"
REPO_URL="https://github.com/AmarJagtap-BTS/Voice_widget.git"
APP_DIR="/home/ubuntu/$APP_NAME"
NODE_VERSION="20"

echo "═══════════════════════════════════════"
echo "  Voice Bot Widget — EC2 Deployment"
echo "  (Ubuntu)"
echo "═══════════════════════════════════════"

# ── 1. System update ──
echo "▸ Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# ── 2. Install Node.js (via NodeSource) ──
echo "▸ Installing Node.js $NODE_VERSION..."
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
sudo apt install -y nodejs
echo "  Node: $(node -v)  |  npm: $(npm -v)"

# ── 3. Install build tools (required by better-sqlite3 native module) ──
echo "▸ Installing build essentials..."
sudo apt install -y build-essential python3 python3-pip git

# ── 4. Install PM2 globally ──
echo "▸ Installing PM2..."
sudo npm install -g pm2

# ── 5. Install Nginx ──
echo "▸ Installing Nginx..."
sudo apt install -y nginx

# ── 6. Clone or update the repository ──
echo "▸ Setting up application..."
if [ -d "$APP_DIR/.git" ]; then
    echo "  Pulling latest from main..."
    cd "$APP_DIR"
    git fetch origin
    git reset --hard origin/main
else
    echo "  Cloning repository..."
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
fi
cd "$APP_DIR"

# ── 7. Install Node.js dependencies ──
echo "▸ Installing Node.js dependencies..."
npm ci --omit=dev

# ── 8. Rebuild native modules for the current Node.js version ──
#       This is required for better-sqlite3 after upgrades or fresh clones.
echo "▸ Rebuilding native modules..."
npm rebuild better-sqlite3

# ── 9. Setup environment file ──
if [ ! -f "$APP_DIR/.env" ]; then
    echo "▸ Creating .env from template..."
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    echo ""
    echo "  ⚠️  ACTION REQUIRED: Fill in your API keys before the app will work!"
    echo "  Run: nano $APP_DIR/.env"
    echo ""
    read -p "  Press Enter after editing .env to continue, or Ctrl+C to stop and edit now..."
fi

# ── 10. Configure Nginx reverse proxy ──
echo "▸ Configuring Nginx..."
sudo tee /etc/nginx/sites-available/$APP_NAME > /dev/null <<'NGINX'
server {
    listen 80;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

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

    # Increase body size for knowledge-base file uploads
    client_max_body_size 50M;
}
NGINX

sudo ln -sf /etc/nginx/sites-available/$APP_NAME /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

# ── 11. Start / restart the app with PM2 ──
echo "▸ Starting application with PM2..."
cd "$APP_DIR"
pm2 delete $APP_NAME 2>/dev/null || true
pm2 start ecosystem.config.js
pm2 save

# Register PM2 to start on reboot
echo "▸ Registering PM2 startup hook..."
PM2_STARTUP_CMD=$(pm2 startup systemd -u ubuntu --hp /home/ubuntu 2>&1 | grep "sudo env" | head -1)
if [ -n "$PM2_STARTUP_CMD" ]; then
    eval "sudo $PM2_STARTUP_CMD" 2>/dev/null || true
fi
pm2 save

PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo '<YOUR_EC2_PUBLIC_IP>')

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ Deployment Complete!"
echo "═══════════════════════════════════════════════"
echo ""
echo "  App URL   : http://$PUBLIC_IP"
echo "  App Dir   : $APP_DIR"
echo "  Logs      : pm2 logs $APP_NAME"
echo "  Status    : pm2 status"
echo "  Restart   : pm2 restart $APP_NAME"
echo "  KB reload : curl http://localhost:3800/api/kb/reload"
echo ""
echo "  📝 Next steps:"
echo "  1. Fill in API keys : nano $APP_DIR/.env  →  pm2 restart $APP_NAME"
echo "  2. Open port 80     : EC2 Console → Security Group → Inbound → HTTP 0.0.0.0/0"
echo "  3. (Optional) HTTPS : sudo apt install -y certbot python3-certbot-nginx"
echo "                        sudo certbot --nginx -d your-domain.com"
echo "═══════════════════════════════════════════════"

