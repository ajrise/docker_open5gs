#!/bin/bash

# 中文注释：
# - 初始化 ims 专用隧道接口
# - 渲染原生 UPF 配置并启动 open5gs-upfd

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export IP_ADDR=$(awk 'END{print $1}' /etc/hosts)
export IF_NAME=$(ip r | awk '/default/ { print $5 }')

update-alternatives --set iptables `which iptables-nft`
update-alternatives --set ip6tables `which ip6tables-nft`

ip link delete $IMS_UPF_APN_IF_NAME 2>/dev/null

if [ "$IMS_UPF_TUNTAP_MODE" = "tap" ]; then
    if [[ "$IMS_UPF_APN_IF_NAME" != *"tap"* ]]; then
        echo "Error: When IMS_UPF_TUNTAP_MODE is 'tap', IMS_UPF_APN_IF_NAME must contain 'tap'"
        exit 1
    fi
elif [ "$IMS_UPF_TUNTAP_MODE" = "tun" ]; then
    if [[ "$IMS_UPF_APN_IF_NAME" == *"tap"* ]]; then
        echo "Error: When IMS_UPF_TUNTAP_MODE is 'tun', IMS_UPF_APN_IF_NAME must not contain 'tap'"
        exit 1
    fi
else
    echo "Error: IMS_UPF_TUNTAP_MODE must be either 'tap' or 'tun'"
    exit 1
fi

python3 /mnt/upf/tun_if.py --tun_ifname $IMS_UPF_APN_IF_NAME --tun_ifmode $IMS_UPF_TUNTAP_MODE --ipv4_range $UE_IPV4_IMS --ipv6_range 2001:230:babe::/48 --no_nat_ipv4_addr $PCSCF_IP --no_nat_ipv6_addr 2001:230:eafe::1 --nat_rule 'no'

UE_IPV4_IMS_TUN_IP=$(python3 /mnt/upf/ip_utils.py --ip_range $UE_IPV4_IMS)

cp /mnt/upf/upf.yaml install/etc/open5gs
sed -i 's|IMS_UPF_IP|'$IMS_UPF_IP'|g' install/etc/open5gs/upf.yaml
sed -i 's|SMF_IP|'$SMF_IP'|g' install/etc/open5gs/upf.yaml
sed -i 's|UE_IPV4_IMS_TUN_IP|'$UE_IPV4_IMS_TUN_IP'|g' install/etc/open5gs/upf.yaml
sed -i 's|UE_IPV4_IMS_SUBNET|'$UE_IPV4_IMS'|g' install/etc/open5gs/upf.yaml
sed -i 's|IMS_UPF_ADVERTISE_IP|'$IMS_UPF_ADVERTISE_IP'|g' install/etc/open5gs/upf.yaml
sed -i 's|MAX_NUM_UE|'$MAX_NUM_UE'|g' install/etc/open5gs/upf.yaml
sed -i 's|IMS_UPF_APN_IF_NAME|'$IMS_UPF_APN_IF_NAME'|g' install/etc/open5gs/upf.yaml

cd install/bin
exec ./open5gs-upfd $@
