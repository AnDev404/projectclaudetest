#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== Mulai setup LAMP & GLPI (port 8080) ==="

# 1) Install dependensi
apt update -y
apt install -y apache2 php8.2-fpm php8.2-mysql php8.2-xml php8.2-curl \
  php8.2-gd php8.2-intl php8.2-zip php8.2-bz2 php8.2-common php8.2-ldap \
  mariadb-server wget unzip curl

# 2) Enable Apache + PHP-FPM
log "Enable Apache modules & PHP-FPM"
a2enmod proxy_fcgi setenvif rewrite
a2enconf php8.2-fpm
sed -i 's/^Listen 80/Listen 8080/' /etc/apache2/ports.conf
sed -i 's/^;*session.cookie_httponly.*/session.cookie_httponly = On/' /etc/php/8.2/fpm/php.ini
set +u; source /etc/apache2/envvars; set -u

# 3) Download & extract GLPI
VER=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
     | grep '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
log "Download GLPI versi $VER"
wget -qO /tmp/glpi.tgz "https://github.com/glpi-project/glpi/releases/download/$VER/glpi-$VER.tgz"

log "Extract GLPI"
rm -rf /var/www/html/glpi
mkdir -p /var/www/html/glpi
tar xf /tmp/glpi.tgz -C /var/www/html/glpi --strip-components=1

# 4) Pindahkan semua kecuali public/ ke folder “core” di luar webroot
log "Restructure GLPI into public/ + core/"
mkdir -p /var/www/glpi-core
shopt -s extglob
mv /var/www/html/glpi/!(public|files) /var/www/glpi-core/
shopt -u extglob

# 5) Relokasi files folder
log "Relocate files folder"
mkdir -p /var/lib/glpi/files
mv /var/www/html/glpi/files/* /var/lib/glpi/files/ 2>/dev/null || true
rm -rf /var/www/html/glpi/files
ln -sf /var/lib/glpi/files /var/www/html/glpi/files
chown -R www-data:www-data /var/lib/glpi/files

# 6) Set perms
log "Set ownership & perms"
chown -R www-data:www-data /var/www/glpi-core /var/www/html/glpi
find /var/www/glpi-core -type d -exec chmod 750 {} \;
find /var/www/glpi-core -type f -exec chmod 640 {} \;
find /var/www/html/glpi -type d -exec chmod 755 {} \;
find /var/www/html/glpi -type f -exec chmod 644 {} \;

# 7) Setup MariaDB
log "Setup MariaDB manual"
mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld
[ ! -d /var/lib/mysql/mysql ] && mysql_install_db --user=mysql --datadir=/var/lib/mysql
mysqld_safe --datadir=/var/lib/mysql --pid-file=/run/mysqld/mysqld.pid & sleep 10

log "Create DB & user"
mysql -uroot -e "CREATE DATABASE IF NOT EXISTS glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -uroot -e "CREATE USER IF NOT EXISTS 'glpiuser'@'localhost' IDENTIFIED BY 'glpipass';"
mysql -uroot -e "GRANT ALL ON glpi.* TO 'glpiuser'@'localhost'; FLUSH PRIVILEGES;"

# 8) Konfigurasi Apache VirtualHost
log "Configure Apache vhost"
cat > /etc/apache2/sites-available/glpi.conf << 'EOF'
<VirtualHost *:8080>
  ServerName localhost

  # Hanya public yang diekspos
  DocumentRoot /var/www/html/glpi/public
  <Directory /var/www/html/glpi/public>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>

  DirectoryIndex index.php
  ErrorLog ${APACHE_LOG_DIR}/glpi_error.log
  CustomLog ${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
EOF

a2dissite 000-default
a2ensite glpi

# 9) Restart services
log "Restart PHP-FPM & Apache"
service php8.2-fpm restart
service apache2 restart

# 10) Autostart
log "Add autostart to .bashrc"
grep -qxF "service apache2 start" /root/.bashrc    || echo "service apache2 start" >> /root/.bashrc
grep -qxF "service php8.2-fpm start" /root/.bashrc || echo "service php8.2-fpm start" >> /root/.bashrc
grep -qxF "mysqld_safe --datadir=/var/lib/mysql --pid-file=/run/mysqld/mysqld.pid &" /root/.bashrc \
  || echo "mysqld_safe --datadir=/var/lib/mysql --pid-file=/run/mysqld/mysqld.pid &" >> /root/.bashrc

log "✅ Setup selesai. Akses GLPI via http://localhost:8080"
