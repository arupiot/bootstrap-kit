#!/bin/bash
# Setup an IoT device within the Arup Corporate Network

if [ "$EUID" -ne 0 ]
  then echo -e "\e[31mThis script must be run as root or using sudo.\e[0m"
  exit
fi

if ping -c 1 proxy.ha.arup.com &> /dev/null
then
  echo -e '\e[32mStarting setup. All normal setup output is logged to setup.log\e[0m'
else
  echo -e "\e[31mThis script will only work within the Arup network.\e[0m"
  exit
fi

cd "$(dirname "$0")"
> setup.log

echo -e '\e[94mDownloading and configuring cntlm proxy...\e[0m'

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
  echo -e 'Please enter your Arup username/password for authentication through the proxy.\e[0m'
  echo -e 'Note these details are stored (hashed) within the /etc/cntlm.conf file and\e[0m'
  echo -e 'someone potentially can gain access to your account with these.\e[0m'

  read -p "Arup Username: \e[0m" username
  echo -e "Arup Password: \e[0m"
  password=$(cntlm -H -d GLOBAL -u $username)

  echo -e '\e[94mCreating configuration...\e[0m'
  if [ -f /etc/cntlm.conf ]; then
     mv /etc/cntlm.conf /etc/cntlm.old.conf
  fi

  echo -e "# CNTLM Config Generated by Arup IoT Setup Script" > /etc/cntlm.conf
  echo -e "Username $username" >> /etc/cntlm.conf
  echo -e "Domain global" >> /etc/cntlm.conf
  echo -e "$password" | sed -n '1!p' >> /etc/cntlm.conf
  echo -e "Proxy proxy.ha.arup.com:80" >> /etc/cntlm.conf
  echo -e "NoProxy localhost, 127.0.0.*, 10.*, 192.168.*" >> /etc/cntlm.conf
  echo -e "Listen 127.0.0.1:3128" >> /etc/cntlm.conf
  echo -e "#NoProxy *" >> /etc/cntlm.conf
fi

grep -q -F 'http_proxy=127.0.0.1:3128' /etc/environment || echo -e 'http_proxy=127.0.0.1:3128' >> /etc/environment
grep -q -F 'https_proxy=127.0.0.1:3128' /etc/environment || echo -e 'https_proxy=127.0.0.1:3128' >> /etc/environment

export http_proxy="http://127.0.0.1:3128"
export https_proxy="http://127.0.0.1:3128"

touch /etc/apt/apt.conf
grep -q -F 'Acquire::http::proxy "http://127.0.0.1:3128/";' /etc/apt/apt.conf || echo -e 'Acquire::http::proxy "http://127.0.0.1:3128/";' >> /etc/apt/apt.conf

service cntlm restart >>setup.log

echo -e '\e[94mChecking connection through the proxy...\e[0m'
if wget -q --no-check-certificate -O /dev/null -o /dev/null "https://google.com/";
then
    echo -e '\e[32mProxy connection appears to be working...\e[0m'
else
    echo -e '\e[31mConnection failed... there may be error messages above or in setup.log to resolve.\e[0m'
    exit
fi

if [ -f /etc/init.d/ntp ]; then
  echo -e '\e[94mUpdating network time server configuration...\e[0m'

  if grep -q -F 'ntp.global.arup.com' /etc/ntp.conf
  then
    :
  else
    if [ -f /etc/ntp.conf ]; then
      mv /etc/ntp.conf /etc/ntp.dist.conf
    fi
  fi

  echo -e "driftfile /var/lib/ntp/ntp.drift
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

echo -e '\e[32mSetup complete.\e[0m'
