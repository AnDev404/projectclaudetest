```bash
pkg install -y proot-distro && proot-distro install debian && proot-distro login debian
```

```bash
apt update
apt install -y wget
wget -O /root/setup_glpi.sh https://raw.githubusercontent.com/AnDev404/projectclaudetest/main/glpi/setup_glpi_full.sh
chmod +x /root/setup_glpi.sh
bash /root/setup_glpi.sh
```
perintah cek ip ditermux :
```bash
hostname -I | awk '{print $1}'
```


```bash
apt update
apt install -y wget
wget -O /root/update_glpi_access.sh "https://raw.githubusercontent.com/AnDev404/projectclaudetest/main/glpi/(update->access%20semua%20ip)%20glpi.sh"
chmod +x /root/update_glpi_access.sh
bash /root/update_glpi_access.sh
```
