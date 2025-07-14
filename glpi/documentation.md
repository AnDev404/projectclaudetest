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
