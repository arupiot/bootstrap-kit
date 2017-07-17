#!/bin/bash
# Arup IoT Bootstrapping Code

if [ "$EUID" -ne 0 ]
  then echo -e "\e[31mThis script must be run as root or using sudo.\e[0m"
  exit
fi

echo -e '\e[94mStarting setup. All normal setup output is logged to setup.log\e[0m'
cd "$(dirname "$0")"
> setup.log

if ping -c 1 8.8.8.8 &> /dev/null
then
  echo -e '\e[32mNetwork connection available\e[0m'
else
  echo -e "\e[31mNo network connection available. Configuring WiFi...\e[0m"
  read -p "SSID: " SSID
  read -p "PSK: " PSK
  grep -q -F $SSID /etc/wpa_supplicant/wpa_supplicant.conf || wpa_passphrase $SSID $PSK >> /etc/wpa_supplicant/wpa_supplicant.conf
  wpa_cli reconfigure >>setup.log
  echo -e "\e[94mWaiting for WiFi to connect...\e[0m"
  while ! ping -c 1 8.8.8.8 &> /dev/null; do
    sleep 1
  done
  echo -e "\e[32mNetwork connection established.\e[0m"
fi

echo -e "\e[94mUpdating Apt and Installing Packages...\e[0m"
apt-get update >>setup.log
apt-get install --assume-yes python vim bash-completion curl git wget pm-utils python-dev python-setuptools libjpeg-dev >>setup.log

echo -e "\e[94mInstalling pip...\e[0m"
if ! type "pip" > /dev/null 2>&1; then
  python < <(curl -s https://bootstrap.pypa.io/get-pip.py) >>setup.log
fi

echo -e "\e[94mInstalling brickd...\e[0m"
wget -q http://download.tinkerforge.com/tools/brickd/linux/brickd_linux_latest_armhf.deb >>setup.log
dpkg --force-confnew -i brickd_linux_latest_armhf.deb >>setup.log 2>>setup.log
rm brickd_linux_latest_armhf.deb

echo -e "\e[94mInstalling/updating deskcontrol...\e[0m"
if [ -d "deskcontrol" ]; then
  cd deskcontrol/
  git pull >>setup.log 2>&1
else
  git clone https://github.com/arupiot/deskcontrol.git >>setup.log
  cd deskcontrol/
fi

pip install -r requirements.txt >>setup.log 2>>setup.log

NEW_UUID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)

read -p "Influx Password: " PASSWORD

echo -e "HOST = 'localhost'

SHORT_IDENT = '$NEW_UUID'

INFLUX_AUTH = {
    'host': '130.211.66.54',
    'port': 8086,
    'user': 'influx',
    'pass': '$PASSWORD',
    'db': 'iotdesks'}" > config_local.py

echo -e "\e[94m(Re)starting deskcontrol...\e[0m"
sudo cp deskcontrol /etc/init.d/deskcontrol
sudo update-rc.d deskcontrol defaults >>setup.log
sudo service deskcontrol restart >>setup.log

echo -e '\e[32mSetup complete.\e[0m'
echo -e "\e[94mDesk UUID: $NEW_UUID\e[0m"
