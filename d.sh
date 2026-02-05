#!/bin/bash
# ===============================================
# Caddy Setup Script: Reverse Proxy + SSL (Let's Encrypt)
# ===============================================

set -e

# -------------------
# USER CONFIGURATION
# -------------------
DOMAIN="sahmcore.com.sa"
ADMIN_EMAIL="a.saeed@$DOMAIN"
# Internal VM IPs
ERP_IP="192.168.116.13"
ERP_PORT="8069"
DOCS_IP="192.168.116.1"
DOCS_PORT="9443"
MAIL_IP="192.168.116.1"
MAIL_PORT="444"
NOMOGROW_IP="192.168.116.48"
NOMOGROW_PORT="8082"
VENTURA_IP="192.168.116.10"
VENTURA_PORT="8080"

# -------------------
# CADDY INSTALLATION (no system update)
# -------------------
echo "[INFO] Installing Caddy..."
if ! command -v caddy >/dev/null 2>&1; then
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt install -y caddy
else
    echo "[INFO] Caddy is already installed."
fi

# -------------------
# STOP OTHER WEB SERVERS (apache2 and nginx)
# -------------------
sudo systemctl stop apache2 nginx 2>/dev/null || true
sudo systemctl disable apache2 nginx 2>/dev/null || true
sudo systemctl mask apache2 nginx  # Ensure Apache and Nginx do not restart

# -------------------
# CREATE CADDYFILE (Reverse Proxy + SSL for the services)
# -------------------
echo "[INFO] Creating Caddyfile for reverse proxy and SSL..."
sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
# WordPress site $DOMAIN, www.$DOMAIN
$DOMAIN, www.$DOMAIN {
    root * /var/www/html  # Assuming WordPress is already installed here
    php_fastcgi unix:/run/php/php8.3-fpm.sock  # Update for your PHP version
    file_server
    encode gzip zstd
    log {
        output file /var/log/caddy/wordpress.log
    }
    header {
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    # SSL (Let's Encrypt automatic)
    tls $ADMIN_EMAIL

    # Redirect HTTP to HTTPS
    redir https://{host}{uri} permanent
}

# ERP Reverse Proxy
erp.$DOMAIN {
    reverse_proxy http://$ERP_IP:$ERP_PORT {
        header_up Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For {remote}
    }
    log {
        output file /var/log/caddy/erp.log
    }
    tls $ADMIN_EMAIL
}

# Documentation Reverse Proxy
docs.$DOMAIN {
    reverse_proxy https://$DOCS_IP:$DOCS_PORT {
        transport http {
            tls_insecure_skip_verify
        }
        header_up Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For {remote}
    }
    log {
        output file /var/log/caddy/docs.log
    }
    tls $ADMIN_EMAIL
}

# Mail Reverse Proxy
mail.$DOMAIN {
    reverse_proxy https://$MAIL_IP:$MAIL_PORT {
        transport http {
            tls_insecure_skip_verify
        }
        header_up Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For {remote}
    }
    log {
        output file /var/log/caddy/mail.log
    }
    tls $ADMIN_EMAIL
}

# Nomogrow Reverse Proxy
nomogrow.$DOMAIN {
    reverse_proxy http://$NOMOGROW_IP:$NOMOGROW_PORT {
        header_up Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For {remote}
    }
    log {
        output file /var/log/caddy/nomogrow.log
    }
    tls $ADMIN_EMAIL
}

# Ventura-Tech Reverse Proxy
ventura-tech.$DOMAIN {
    reverse_proxy http://$VENTURA_IP:$VENTURA_PORT {
        header_up Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For {remote}
    }
    log {
        output file /var/log/caddy/ventura-tech.log
    }
    tls $ADMIN_EMAIL
}

# HTTP redirect to HTTPS for debugging
http://$DOMAIN, http://www.$DOMAIN, http://erp.$DOMAIN, http://docs.$DOMAIN, http://mail.$DOMAIN, http://nomogrow.$DOMAIN, http://ventura-tech.$DOMAIN {
    redir https://{host}{uri} permanent
}
EOF

# -------------------
# FIREWALL SETUP (Allow HTTP and HTTPS traffic)
# -------------------
echo "[INFO] Configuring firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp  # SSH
sudo ufw allow 80/tcp  # HTTP (for Let's Encrypt)
sudo ufw allow 443/tcp # HTTPS
sudo ufw enable

# -------------------
# START CADDY
# -------------------
echo "[INFO] Starting Caddy..."
sudo systemctl daemon-reload
sudo systemctl enable --now caddy

# -------------------
# FORCE RUN THE ACME CHALLENGE (SSL issuance)
# -------------------
echo "[INFO] Forcing Caddy to run ACME challenge to get Let's Encrypt SSL certificate..."
sudo caddy certs -force

# -------------------
# DIAGNOSTIC SCRIPT STARTS HERE
# -------------------
echo "[INFO] Starting Caddy Diagnostic Check..."

# Check if Caddy is running
echo "[INFO] Checking if Caddy is running..."
if systemctl is-active --quiet caddy; then
    echo "[INFO] Caddy is running."
else
    echo "[ERROR] Caddy is NOT running. Starting Caddy..."
    sudo systemctl start caddy
    sudo systemctl enable caddy
fi

# Check Caddy status
echo "[INFO] Checking the status of Caddy..."
sudo systemctl status caddy

# Check the Let's Encrypt certificate status
echo "[INFO] Checking the status of Let's Encrypt certificate for $DOMAIN..."
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "[INFO] Let's Encrypt SSL certificate found for $DOMAIN."
else
    echo "[ERROR] SSL certificate not found for $DOMAIN."
fi

# -------------------
# Final Status
# -------------------
echo ""
echo "==============================================="
echo "Caddy Setup Complete!"
echo "==============================================="
echo "WordPress should now be accessible at https://$DOMAIN"
echo "ERP: https://erp.$DOMAIN"
echo "Docs: https://docs.$DOMAIN"
echo "Mail: https://mail.$DOMAIN"
echo "Nomogrow: https://nomogrow.$DOMAIN"
echo "Ventura-Tech: https://ventura-tech.$DOMAIN"
echo "SSL certificates are managed automatically by Let's Encrypt."
echo "==============================================="
