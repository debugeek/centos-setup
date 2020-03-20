#!/bin/bash

set -e

version_compare () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

#
# fail2ban
#
installFail2ban() {
    yum install -y fail2ban

    cat > /etc/fail2ban/jail.local <<EOF
[ssh-iptables]
enabled = true
filter = sshd
action = iptables[name=SSH, port=ssh, protocol=tcp]
logpath = /var/log/secure
maxretry = 5
EOF

    systemctl restart fail2ban.service
    systemctl enable fail2ban
}

#
# BBR
#
installBBR() {
    if [[ $(version_compare $(uname -r) "4.9") == 2 ]] ;then
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
        yum-config-manager --enable elrepo-kernel
        yum install kernel-ml -y
        egrep ^menuentry /etc/grub2.cfg | cut -f 2 -d \'
        grub2-set-default 0
        reboot
        exit 0
    else
        cat > /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

        sysctl -p
        
        sysctl net.ipv4.tcp_available_congestion_control
        lsmod | grep bbr
    fi
}

#
# V2Ray
#
installV2Ray() {
    curl -fsSL https://install.direct/go.sh | sh

    while true; do
        read -p "Please input the PORT for v2ray [1-65535]:" v2port
        if [ $v2port -ge 1 ] && [ $v2port -le 65535 ]; then
            break
        else
            echo "NOT AVAILABLE PORT NUMBER"
        fi
    done

    while true; do
        read -p "Please input the UUID for v2ray:" v2uuid
        if [[ ${v2uuid//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
            break
        else
            echo "NOT AVAILABLE UUID"
        fi
    done

    while true; do
        read -p "Please input the ALTERID for v2ray [1-9999]:" v2alterId
        if [ $v2alterId -ge 1 ] && [ $v2alterId -le 9999 ]; then
            break
        else
            echo "NOT AVAILABLE ALTERID"
        fi
    done

    cat > /etc/v2ray/config.json <<EOF
{
    "log": {
        "access": "/var/log/v2ray/access.log",
        "error": "/var/log/v2ray/error.log",
        "loglevel": "warning"
    },
    "inbound": {
        "port": $v2port,
        "protocol": "vmess",
        "settings": {
            "clients": [
                {
                    "id": "$v2uuid",
                    "level": 1,
                    "alterId": $v2alterId
                }
            ]
        }
    },
    "outbound": {
        "protocol": "freedom",
        "settings": {}
    },
    "inboundDetour": [],
    "outboundDetour": [
        {
            "protocol": "blackhole",
            "settings": {},
            "tag": "blocked"
        }
    ],
    "routing": {
        "strategy": "rules",
        "settings": {
            "rules": [
                {
                    "type": "field",
                    "ip": [
                        "0.0.0.0/8",
                        "10.0.0.0/8",
                        "100.64.0.0/10",
                        "127.0.0.0/8",
                        "169.254.0.0/16",
                        "172.16.0.0/12",
                        "192.0.0.0/24",
                        "192.0.2.0/24",
                        "192.168.0.0/16",
                        "198.18.0.0/15",
                        "198.51.100.0/24",
                        "203.0.113.0/24",
                        "::1/128",
                        "fc00::/7",
                        "fe80::/10"
                    ],
                    "outboundTag": "blocked"
                }
            ]
        }
    }
}
EOF

    systemctl restart v2ray
    systemctl enable v2ray

    firewall-cmd --permanent --add-port=$v2port/tcp
    firewall-cmd --permanent --add-port=$v2port/udp
    firewall-cmd --reload
}


#
# Nginx
#
installNginx() {
    yum install nginx -y

    systemctl start nginx
    systemctl enable nginx

    sudo firewall-cmd --permanent --zone=public --add-service=https --add-service=http
    sudo firewall-cmd --reload
}



yum update -y
yum upgrade -y

yum install epel-release -y
yum install yum-utils -y

# Firewall
systemctl start firewalld

read -p "Shall I Install Fail2ban (y/n)? " fail2ban
if [ "$fail2ban" != "${fail2ban#[Yy]}" ] ;then
    installFail2ban
fi

read -p "Shall I Install BBR (y/n)? " bbr
if [ "$bbr" != "${bbr#[Yy]}" ] ;then
    installBBR
fi

read -p "Shall I Install V2Ray (y/n)? " v2ray
if [ "$v2ray" != "${v2ray#[Yy]}" ] ;then
    installV2Ray
fi

read -p "Shall I Install Nginx (y/n)? " nginx
if [ "$nginx" != "${nginx#[Yy]}" ] ;then
    installNginx
fi