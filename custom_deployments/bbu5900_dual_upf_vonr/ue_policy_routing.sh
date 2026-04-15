#!/usr/bin/env bash
set -euo pipefail

# Manage host policy routing for UE subnets.
# Usage:
#   sudo ./ue_policy_routing.sh apply
#   sudo ./ue_policy_routing.sh status
#   sudo ./ue_policy_routing.sh remove

MODE="${1:-status}"
SCENARIO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCENARIO_DIR}/.custom_env"
SERVICE_NAME="ue-policy-routing.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
SYSCTL_NAME="99-open5gs-dual-n3.conf"
SYSCTL_PATH="/etc/sysctl.d/${SYSCTL_NAME}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: missing ${ENV_FILE}"
  exit 1
fi

# shellcheck disable=SC1090
source <(tr -d '\r' < "${ENV_FILE}")

: "${UE_IPV4_INTERNET:?UE_IPV4_INTERNET is required in .custom_env}"
: "${UE_IPV4_IMS:?UE_IPV4_IMS is required in .custom_env}"
: "${N6_IF:?N6_IF is required in .custom_env}"
: "${N6_GATEWAY:?N6_GATEWAY is required in .custom_env}"
: "${UE_POLICY_TABLE:?UE_POLICY_TABLE is required in .custom_env}"
: "${UE_POLICY_PRIO_INTERNET:?UE_POLICY_PRIO_INTERNET is required in .custom_env}"
: "${UE_POLICY_PRIO_IMS:?UE_POLICY_PRIO_IMS is required in .custom_env}"

N3_SUBNET="${N3_SUBNET:-10.10.10.0/24}"
IMS_N3_IF="${IMS_N3_IF:-}"
EUPF_N3_IF="${EUPF_N3_IF:-}"

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: run as root"
    exit 1
  fi
}

ensure_multihome_sysctls() {
  sysctl -w net.ipv4.conf.all.arp_ignore=1 >/dev/null || true
  sysctl -w net.ipv4.conf.all.arp_announce=2 >/dev/null || true
  sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null || true
  sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null || true

  for ifname in "${N6_IF}" "${IMS_N3_IF}" "${EUPF_N3_IF}"; do
    [[ -n "${ifname}" ]] || continue
    sysctl -w "net.ipv4.conf.${ifname}.rp_filter=0" >/dev/null || true
  done
}

write_sysctl_config() {
  cat > "${SYSCTL_PATH}" <<EOF
net.ipv4.conf.all.arp_ignore=1
net.ipv4.conf.all.arp_announce=2
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF

  for ifname in "${N6_IF}" "${IMS_N3_IF}" "${EUPF_N3_IF}"; do
    [[ -n "${ifname}" ]] || continue
    echo "net.ipv4.conf.${ifname}.rp_filter=0" >> "${SYSCTL_PATH}"
  done

  sysctl --system >/dev/null 2>&1 || true
}

apply_n3_source_policy() {
  if [[ -n "${IMS_N3_IF}" ]]; then
    ip route replace "${N3_SUBNET}" dev "${IMS_N3_IF}" src "${IMS_UPF_ADVERTISE_IP}" table 100
    ip rule del from "${IMS_UPF_ADVERTISE_IP}/32" table 100 2>/dev/null || true
    ip rule add from "${IMS_UPF_ADVERTISE_IP}/32" table 100 priority 100
  fi

  if [[ -n "${EUPF_N3_IF}" ]]; then
    ip route replace "${N3_SUBNET}" dev "${EUPF_N3_IF}" src "${UPF_ADVERTISE_IP}" table 101
    ip rule del from "${UPF_ADVERTISE_IP}/32" table 101 2>/dev/null || true
    ip rule add from "${UPF_ADVERTISE_IP}/32" table 101 priority 101
  fi
}

remove_n3_source_policy() {
  ip rule del from "${IMS_UPF_ADVERTISE_IP}/32" table 100 2>/dev/null || true
  ip rule del from "${UPF_ADVERTISE_IP}/32" table 101 2>/dev/null || true

  if [[ -n "${IMS_N3_IF}" ]]; then
    ip route del "${N3_SUBNET}" dev "${IMS_N3_IF}" src "${IMS_UPF_ADVERTISE_IP}" table 100 2>/dev/null || true
  fi

  if [[ -n "${EUPF_N3_IF}" ]]; then
    ip route del "${N3_SUBNET}" dev "${EUPF_N3_IF}" src "${UPF_ADVERTISE_IP}" table 101 2>/dev/null || true
  fi
}

write_service() {
  cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=UE subnet policy routing via ${N6_IF}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sysctl -w net.ipv4.conf.all.arp_ignore=1 >/dev/null || true; sysctl -w net.ipv4.conf.all.arp_announce=2 >/dev/null || true; sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null || true; sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null || true; sysctl -w net.ipv4.conf.${N6_IF}.rp_filter=0 >/dev/null || true; [ -z "${IMS_N3_IF}" ] || sysctl -w net.ipv4.conf.${IMS_N3_IF}.rp_filter=0 >/dev/null || true; [ -z "${EUPF_N3_IF}" ] || sysctl -w net.ipv4.conf.${EUPF_N3_IF}.rp_filter=0 >/dev/null || true; ip route replace default via ${N6_GATEWAY} dev ${N6_IF} table ${UE_POLICY_TABLE}; ip rule del from ${UE_IPV4_INTERNET} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip rule del from ${UE_IPV4_IMS} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip rule add from ${UE_IPV4_INTERNET} table ${UE_POLICY_TABLE} priority ${UE_POLICY_PRIO_INTERNET}; ip rule add from ${UE_IPV4_IMS} table ${UE_POLICY_TABLE} priority ${UE_POLICY_PRIO_IMS}; [ -z "${IMS_N3_IF}" ] || { ip route replace ${N3_SUBNET} dev ${IMS_N3_IF} src ${IMS_UPF_ADVERTISE_IP} table 100; ip rule del from ${IMS_UPF_ADVERTISE_IP}/32 table 100 2>/dev/null || true; ip rule add from ${IMS_UPF_ADVERTISE_IP}/32 table 100 priority 100; }; [ -z "${EUPF_N3_IF}" ] || { ip route replace ${N3_SUBNET} dev ${EUPF_N3_IF} src ${UPF_ADVERTISE_IP} table 101; ip rule del from ${UPF_ADVERTISE_IP}/32 table 101 2>/dev/null || true; ip rule add from ${UPF_ADVERTISE_IP}/32 table 101 priority 101; }; iptables -t nat -C POSTROUTING -s ${UE_IPV4_INTERNET} -o ${N6_IF} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${UE_IPV4_INTERNET} -o ${N6_IF} -j MASQUERADE; iptables -t nat -C POSTROUTING -s ${UE_IPV4_IMS} -o ${N6_IF} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${UE_IPV4_IMS} -o ${N6_IF} -j MASQUERADE'
ExecStop=/bin/sh -c 'iptables -t nat -D POSTROUTING -s ${UE_IPV4_INTERNET} -o ${N6_IF} -j MASQUERADE 2>/dev/null || true; iptables -t nat -D POSTROUTING -s ${UE_IPV4_IMS} -o ${N6_IF} -j MASQUERADE 2>/dev/null || true; ip rule del from ${UE_IPV4_INTERNET} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip rule del from ${UE_IPV4_IMS} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip route del default via ${N6_GATEWAY} dev ${N6_IF} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip rule del from ${IMS_UPF_ADVERTISE_IP}/32 table 100 2>/dev/null || true; ip rule del from ${UPF_ADVERTISE_IP}/32 table 101 2>/dev/null || true; [ -z "${IMS_N3_IF}" ] || ip route del ${N3_SUBNET} dev ${IMS_N3_IF} src ${IMS_UPF_ADVERTISE_IP} table 100 2>/dev/null || true; [ -z "${EUPF_N3_IF}" ] || ip route del ${N3_SUBNET} dev ${EUPF_N3_IF} src ${UPF_ADVERTISE_IP} table 101 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

ensure_nat() {
  iptables -t nat -C POSTROUTING -s "${UE_IPV4_INTERNET}" -o "${N6_IF}" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "${UE_IPV4_INTERNET}" -o "${N6_IF}" -j MASQUERADE
  iptables -t nat -C POSTROUTING -s "${UE_IPV4_IMS}" -o "${N6_IF}" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "${UE_IPV4_IMS}" -o "${N6_IF}" -j MASQUERADE
}

remove_nat() {
  iptables -t nat -D POSTROUTING -s "${UE_IPV4_INTERNET}" -o "${N6_IF}" -j MASQUERADE 2>/dev/null || true
  iptables -t nat -D POSTROUTING -s "${UE_IPV4_IMS}" -o "${N6_IF}" -j MASQUERADE 2>/dev/null || true
}

apply_policy() {
  ensure_root

  ensure_multihome_sysctls
  write_sysctl_config
  ip route replace default via "${N6_GATEWAY}" dev "${N6_IF}" table "${UE_POLICY_TABLE}"
  ip rule del from "${UE_IPV4_INTERNET}" table "${UE_POLICY_TABLE}" 2>/dev/null || true
  ip rule del from "${UE_IPV4_IMS}" table "${UE_POLICY_TABLE}" 2>/dev/null || true
  ip rule add from "${UE_IPV4_INTERNET}" table "${UE_POLICY_TABLE}" priority "${UE_POLICY_PRIO_INTERNET}"
  ip rule add from "${UE_IPV4_IMS}" table "${UE_POLICY_TABLE}" priority "${UE_POLICY_PRIO_IMS}"
  apply_n3_source_policy
  ensure_nat

  write_service
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}"

  echo "Applied and persisted policy routing."
  status_policy
}

remove_policy() {
  ensure_root

  ip rule del from "${UE_IPV4_INTERNET}" table "${UE_POLICY_TABLE}" 2>/dev/null || true
  ip rule del from "${UE_IPV4_IMS}" table "${UE_POLICY_TABLE}" 2>/dev/null || true
  ip route del default via "${N6_GATEWAY}" dev "${N6_IF}" table "${UE_POLICY_TABLE}" 2>/dev/null || true
  remove_n3_source_policy
  remove_nat

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
    systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
  fi

  rm -f "${SERVICE_PATH}"
  rm -f "${SYSCTL_PATH}"
  systemctl daemon-reload

  echo "Removed policy routing and persistence service."
  status_policy
}

status_policy() {
  echo "=== Policy Rules ==="
  ip rule show | grep -E "${UE_POLICY_TABLE}|from ${UE_IPV4_INTERNET}|from ${UE_IPV4_IMS}" || true

  echo "=== Table ${UE_POLICY_TABLE} ==="
  ip route show table "${UE_POLICY_TABLE}" || true

  echo "=== NAT Rules ==="
  iptables -t nat -S | grep -E "${UE_IPV4_INTERNET}|${UE_IPV4_IMS}|${N6_IF}" || true

  echo "=== Multi-homed Sysctls ==="
  sysctl net.ipv4.conf.all.arp_ignore net.ipv4.conf.all.arp_announce net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter 2>/dev/null || true
  [[ -n "${IMS_N3_IF}" ]] && sysctl "net.ipv4.conf.${IMS_N3_IF}.rp_filter" 2>/dev/null || true
  [[ -n "${EUPF_N3_IF}" ]] && sysctl "net.ipv4.conf.${EUPF_N3_IF}.rp_filter" 2>/dev/null || true
  sysctl "net.ipv4.conf.${N6_IF}.rp_filter" 2>/dev/null || true

  echo "=== Route Decisions ==="
  ip route get 8.8.8.8 from "${UE_IPV4_INTERNET%%/*}" iif "${N6_IF}" 2>/dev/null || true
  ip route get 8.8.8.8 from "${UE_IPV4_IMS%%/*}" iif "${N6_IF}" 2>/dev/null || true

  echo "=== Persistence Files ==="
  [[ -f "${SYSCTL_PATH}" ]] && echo "present: ${SYSCTL_PATH}" || echo "missing: ${SYSCTL_PATH}"
  [[ -f "${SERVICE_PATH}" ]] && echo "present: ${SERVICE_PATH}" || echo "missing: ${SERVICE_PATH}"

  echo "=== Service Status ==="
  systemctl is-enabled "${SERVICE_NAME}" 2>/dev/null || echo "disabled"
  systemctl is-active "${SERVICE_NAME}" 2>/dev/null || echo "inactive"
}

case "${MODE}" in
  apply)
    apply_policy
    ;;
  remove)
    remove_policy
    ;;
  status)
    status_policy
    ;;
  *)
    echo "Usage: $0 [apply|status|remove]"
    exit 1
    ;;
esac
