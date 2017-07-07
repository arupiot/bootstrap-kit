#!/bin/bash
# Setup an IoT device within the Arup Corporate Network

if [ "$EUID" -ne 0 ]
  then echo "This script must be run as root or using sudo."
  exit
fi

if ping -c 1 proxy.ha.arup.com &> /dev/null
then
  echo 'Starting setup. All normal setup output is logged to setup.log'
else
  echo "This script will only work within the Arup network."
  exit
fi

cd "$(dirname "$0")"
> setup.log

echo 'Downloading and configuring cntlm proxy...'

codename=$(awk -F"[)(]+" '/VERSION=/ {print $2}' /etc/os-release)
arch=$(dpkg --print-architecture)

wget -q http://iot.arup.com/packages/$codename/cntlm_$arch.deb >>setup.log
dpkg --force-confnew -i cntlm_$arch.deb >>setup.log 2>>setup.log
rm cntlm_$arch.deb

do_config=false
if grep -q -F 'proxy.ha.arup.com' /etc/cntlm.conf
then
  read -r -n 1 -p "Proxy Configuration already exists, do you want to replace it? (y/N) " replace_config
  echo
  if [[ $replace_config =~ ^[Yy]$ ]]
  then
    do_config=true
  fi
else
  do_config=true
fi

if $do_config;
then
  echo 'Please enter your Arup username/password for authentication through the proxy.'
  echo 'Note these details are stored (hashed) within the /etc/cntlm.conf file and'
  echo 'someone potentially can gain access to your account with these.'

  read -p "Arup Username: " username
  echo "Arup Password: "
  password=$(cntlm -H -d GLOBAL -u $username)

  echo 'Creating configuration...'
  if [ -f /etc/cntlm.conf ]; then
     mv /etc/cntlm.conf /etc/cntlm.old.conf
  fi

  echo "# CNTLM Config Generated by Arup IoT Setup Script" > /etc/cntlm.conf
  echo "Username $username" >> /etc/cntlm.conf
  echo "Domain global" >> /etc/cntlm.conf
  echo "$password" | sed -n '1!p' >> /etc/cntlm.conf
  echo "Proxy proxy.ha.arup.com:80" >> /etc/cntlm.conf
  echo "NoProxy localhost, 127.0.0.*, 10.*, 192.168.*" >> /etc/cntlm.conf
  echo "Listen 127.0.0.1:3128" >> /etc/cntlm.conf
fi

grep -q -F 'http_proxy=127.0.0.1:3128' /etc/environment || echo 'http_proxy=127.0.0.1:3128' >> /etc/environment
grep -q -F 'https_proxy=127.0.0.1:3128' /etc/environment || echo 'https_proxy=127.0.0.1:3128' >> /etc/environment

export http_proxy="http://127.0.0.1:3128"
export https_proxy="http://127.0.0.1:3128"

touch /etc/apt/apt.conf
grep -q -F 'Acquire::http::proxy "http://127.0.0.1:3128/";' /etc/apt/apt.conf || echo 'Acquire::http::proxy "http://127.0.0.1:3128/";' >> /etc/apt/apt.conf

service cntlm restart >>setup.log

echo 'Checking connection through the proxy...'
if wget -q --no-check-certificate -O /dev/null -o /dev/null "https://google.com/";
then
    echo 'Proxy connection appears to be working...'
else
    echo 'Connection failed... there may be error messages above or in setup.log to resolve.'
    exit
fi

if [ -f /etc/init.d/ntp ]; then
  echo 'Updating network time server configuration...'

  if grep -q -F 'ntp.global.arup.com' /etc/ntp.conf
  then
    :
  else
    if [ -f /etc/ntp.conf ]; then
      mv /etc/ntp.conf /etc/ntp.dist.conf
    fi
  fi

  echo "driftfile /var/lib/ntp/ntp.drift
  server ntp.global.arup.com
  restrict ntp.global.arup.com mask 255.255.255.255 nomodify notrap noquery
  server ntp01.global.arup.com
  restrict ntp01.global.arup.com mask 255.255.255.255 nomodify notrap noquery
  server ntp02.global.arup.com
  restrict ntp02.global.arup.com mask 255.255.255.255 nomodify notrap noquery
  restrict -4 default kod notrap nomodify nopeer noquery
  restrict -6 default kod notrap nomodify nopeer noquery
  restrict 127.0.0.1
  restrict ::1" >> /etc/ntp.conf

  service ntp stop >>setup.log
  ntpd -gq >>setup.log
  service ntp start >>setup.log
fi

read -r -n 1 -p "Do you need to be able to connect while not on the Arup network? (y/N) " ext_proxy
echo
if [[ $ext_proxy =~ ^[Yy]$ ]]
then
  echo 'Updating aptitude repository...'

  apt-get update >>setup.log

  echo 'Downloading and configuring tinyproxy...'

  apt-get install --assume-yes tinyproxy >>setup.log

  grep -q -F 'Proxy localhost:3129' /etc/cntlm.conf || echo 'Proxy localhost:3129' >> /etc/cntlm.conf

  sed -i -e 's/Port 8888/#Port 8888/g' /etc/tinyproxy.conf
  grep -q -F 'Port 3129' /etc/tinyproxy.conf || echo 'Port 3129' >> /etc/tinyproxy.conf
  grep -q -F 'Allow 127.0.0.1' /etc/tinyproxy.conf || echo 'Allow 127.0.0.1' >> /etc/tinyproxy.conf

  service tinyproxy restart >>setup.log
  service cntlm restart >>setup.log

  echo 'Checking connection through the proxy...'
  if wget -q -O /dev/null -o /dev/null "https://google.com/";
  then
      echo 'Proxy connection appears to be working...'
  else
      echo 'Connection failed... there may be error messages above or in setup.log to resolve.'
      exit
  fi
fi

echo 'Setup complete.'