#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log "=== Mulai setup LAMP & GLPI (port 8080) ==="

# 1) Update & install dependensi
apt update -y
apt install -y apache2 \
  php8.2-fpm php8.2-mysql php8.2-xml php8.2-curl \
  php8.2-gd php8.2-intl php8.2-zip php8.2-bz2 \
  php8.2-common php8.2-ldap \
  mariadb-server wget unzip curl

# 2) Enable Apache modules & PHP-FPM
log "Enable Apache modules & PHP-FPM"
a2enmod proxy_fcgi setenvif rewrite
a2enconf php8.2-fpm

# 3) Ubah port Apache ke 8080
log "Set Apache Listen → 8080"
sed -i 's/^Listen 80/Listen 8080/' /etc/apache2/ports.conf

# 4) Aktifkan httponly di session cookie
log "Enable session.cookie_httponly"
sed -i 's/^;*session.cookie_httponly.*/session.cookie_httponly = On/' /etc/php/8.2/fpm/php.ini

# 5) Load Apache envvars
set +u; source /etc/apache2/envvars; set -u

# 6) Download & extract GLPI
VER=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
     | grep '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
log "Download GLPI versi $VER"
wget -qO /tmp/glpi.tgz \
     "https://github.com/glpi-project/glpi/releases/download/$VER/glpi-$VER.tgz"

log "Extract ke /var/www/html/glpi"
rm -rf /var/www/html/glpi
mkdir -p /var/www/html/glpi
tar xf /tmp/glpi.tgz -C /var/www/html/glpi --strip-components=1

# 7) Relocate files folder
log "Relocate files folder"
mkdir -p /var/lib/glpi/files
if [ -d /var/www/html/glpi/files ]; then
  mv /var/www/html/glpi/files/* /var/lib/glpi/files/
  rm -rf /var/www/html/glpi/files
fi
ln -sf /var/lib/glpi/files /var/www/html/glpi/files
chown -R www-data:www-data /var/lib/glpi/files

# 8) Set ownership & perms
log "Set ownership & perms"
chown -R www-data:www-data /var/www/html/glpi
find /var/www/html/glpi -type d -exec chmod 755 {} \;
find /var/www/html/glpi -type f -exec chmod 644 {} \;

# 9) Jalankan MariaDB manual
log "Setup MariaDB manual"
mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld
if [ ! -d /var/lib/mysql/mysql ]; then
  mysql_install_db --user=mysql --datadir=/var/lib/mysql
fi
mysqld_safe --datadir=/var/lib/mysql --pid-file=/run/mysqld/mysqld.pid &
sleep 10

# 10) Buat DB & user GLPI
log "Create DB & user GLPI"
mysql -uroot -e "CREATE DATABASE IF NOT EXISTS glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -uroot -e "CREATE USER IF NOT EXISTS 'glpiuser'@'localhost' IDENTIFIED BY 'glpipass';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON glpi.* TO 'glpiuser'@'localhost'; FLUSH PRIVILEGES;"

# 11) Konfigurasi VirtualHost Apache
log "Configure Apache vhost"
cat > /etc/apache2/sites-available/glpi.conf << 'EOF'
<VirtualHost *:8080>
  ServerName localhost
  DocumentRoot /var/www/html/glpi

  <Directory /var/www/html/glpi>
    Options Indexes FollowSymLinks
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

# 12) Restart services
log "Restart PHP-FPM & Apache"
service php8.2-fpm restart
service apache2 restart

# 13) Autostart di .bashrc
log "Add autostart to .bashrc"
grep -qxF "service apache2 start" /root/.bashrc    || echo "service apache2 start" >> /root/.bashrc
grep -qxF "service php8.2-fpm start" /root/.bashrc || echo "service php8.2-fpm start" >> /root/.bashrc
grep -qxF "mysqld_safe --datadir=/var/lib/mysql --pid-file=/run/mysqld/mysqld.pid &" /root/.bashrc \
  || echo "mysqld_safe --datadir=/var/lib/mysql --pid-file=/run/mysqld/mysqld.pid &" >> /root/.bashrc

log "✅ Setup selesai. Akses GLPI via http://localhost:8080"
