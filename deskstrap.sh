#!/bin/bash
# Arup IoT Bootstrapping Code

if [ "$EUID" -ne 0 ]
  then echo "This script must be run as root or using sudo."
  exit
fi

echo 'Starting setup. All normal setup output is logged to setup.log'
cd "$(dirname "$0")"
> setup.log

if ping -c 1 8.8.8.8 &> /dev/null
then
  echo 'Network connection available'
else
  echo "No network connection available. Configuring WiFi..."
  read -p "SSID: " SSID
  read -p "PSK: " PSK
  grep -q -F $SSID /etc/wpa_supplicant/wpa_supplicant.conf || wpa_passphrase $SSID $PSK >> /etc/wpa_supplicant/wpa_supplicant.conf
  wpa_cli reconfigure >>setup.log
  echo "Waiting for WiFi to connect..."
  while ! ping -c 1 8.8.8.8 &> /dev/null; do
    sleep 1
  done
  echo "Network connection established."
fi

echo "Updating Apt and Installing Packages..."
apt-get update >>setup.log
apt-get install --assume-yes python vim bash-completion curl git wget pm-utils >>setup.log

echo "Installing pip..."
if ! type "pip" > /dev/null 2>&1; then
  python < <(curl -s https://bootstrap.pypa.io/get-pip.py) >>setup.log
fi

echo "Installing brickd..."
wget -q http://download.tinkerforge.com/tools/brickd/linux/brickd_linux_latest_armhf.deb >>setup.log
dpkg --force-confnew -i brickd_linux_latest_armhf.deb >>setup.log 2>>setup.log
rm brickd_linux_latest_armhf.deb

echo "Installing/updating deskcontrol..."
if [ -d "deskcontrol" ]; then
  cd deskcontrol/
  git pull >>setup.log 2>&1
else
  git clone https://github.com/arupiot/deskcontrol.git >>setup.log
  cd deskcontrol/
fi

pip install -r requirements.txt

NEW_UUID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)

read -p "Influx Password: " PASSWORD

echo "SHORT_IDENT = '$NEW_UUID'

INFLUX_AUTH = {
    'host': '130.211.66.54',
    'port': 8086,
    'user': 'influx',
    'pass': '$PASSWORD',
    'db': 'iotdesks'}" > config_local.py

echo "(Re)starting deskcontrol..."
sudo cp deskcontrol /etc/init.d/deskcontrol
sudo update-rc.d deskcontrol defaults >>setup.log
sudo service deskcontrol restart >>setup.log

echo 'Setup complete.'
echo "Desk UUID: $NEW_UUID"
