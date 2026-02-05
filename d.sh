#!/bin/bash

# ================================================
# Fix Apache SSL and Install Let's Encrypt Certificate
# ================================================

set -e

# Variables
DOMAIN="sahmcore.com.sa"
WEB_ROOT="/var/www/html"
CERTBOT_EMAIL="admin@$DOMAIN"
APACHE_CONF="/etc/apache2/sites-available/sahmcore.com.sa.conf"
SSL_CONF="/etc/apache2/sites-available/sahmcore-ssl.conf"  # This will be the new SSL conf file
LETS_ENCRYPT_PATH="/etc/letsencrypt/live/$DOMAIN"
CERTBOT_PATH="/usr/bin/certbot"

# Step 1: Disable SSL Configuration Temporarily
echo "[INFO] Disabling SSL configuration temporarily..."

# Backup the Apache config file
cp $APACHE_CONF ${APACHE_CONF}.bak

# Comment out SSL-related lines to prevent configtest errors
sed -i 's/SSLEngine on/#SSLEngine on/' $APACHE_CONF
sed -i 's|SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/cert.pem|#SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/cert.pem|' $APACHE_CONF
sed -i 's|SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem|#SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem|' $APACHE_CONF
sed -i 's|SSLCertificateChainFile /etc/letsencrypt/live/$DOMAIN/chain.pem|#SSLCertificateChainFile /etc/letsencrypt/live/$DOMAIN/chain.pem|' $APACHE_CONF

# Step 2: Disable SSL Site Config Temporarily (If Exists)
echo "[INFO] Disabling SSL site config..."
if [ -f "/etc/apache2/sites-available/000-default-ssl.conf" ]; then
    sudo a2dissite 000-default-ssl.conf
fi

# Step 3: Run Apache configtest
echo "[INFO] Running Apache configtest..."
sudo apache2ctl configtest

# Step 4: Restart Apache to apply non-SSL changes
echo "[INFO] Restarting Apache to apply changes..."
sudo systemctl restart apache2

# Step 5: Install/renew SSL certificates using Certbot
echo "[INFO] Installing or renewing SSL certificates using Certbot..."

# Run Certbot to get SSL certificates for the domain
sudo certbot --apache -d $DOMAIN -d www.$DOMAIN --email $CERTBOT_EMAIL --agree-tos --no-eff-email --redirect

# Check if Certbot was successful
if [ $? -ne 0 ]; then
  echo "[ERROR] Certbot failed to obtain a certificate. Please check the errors above."
  exit 1
fi

# Step 6: Create SSL Configuration File (if it doesn't exist)
echo "[INFO] Creating SSL configuration file..."

# Create the SSL virtual host configuration file
sudo tee $SSL_CONF > /dev/null <<EOF
<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot $WEB_ROOT
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/$DOMAIN/chain.pem

    # Additional SSL settings
    SSLProtocol all -SSLv2 -SSLv3
    SSLCipherSuite HIGH:!aNULL:!MD5
    SSLHonorCipherOrder on

    # Custom Logging
    LogLevel warn
    CustomLog /var/log/apache2/$DOMAIN-access.log combined
    ErrorLog /var/log/apache2/$DOMAIN-error.log

    # Additional security headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
</VirtualHost>
EOF

# Step 7: Enable the SSL Site Configuration
echo "[INFO] Enabling SSL site configuration..."

sudo a2ensite $SSL_CONF

# Step 8: Enable SSL Module
echo "[INFO] Enabling SSL module..."
sudo a2enmod ssl

# Step 9: Run Apache configtest again to check the configuration
echo "[INFO] Running Apache configtest again to verify SSL settings..."
sudo apache2ctl configtest

# Step 10: Restart Apache to apply SSL changes
echo "[INFO] Restarting Apache to apply SSL configuration..."
sudo systemctl restart apache2

# Step 11: Verify SSL Installation
echo "[INFO] Verifying SSL certificate installation..."
if [ -d "$LETS_ENCRYPT_PATH" ]; then
  echo "[INFO] SSL certificate installed successfully. Certificate path: $LETS_ENCRYPT_PATH"
else
  echo "[ERROR] SSL certificate installation failed. No certificate found at $LETS_ENCRYPT_PATH"
  exit 1
fi

# Step 12: Automatic Renewal Setup (Certbot should already set this up)
echo "[INFO] Testing Certbot renewal..."
sudo certbot renew --dry-run

echo "[INFO] SSL certificate installation and Apache configuration complete."
