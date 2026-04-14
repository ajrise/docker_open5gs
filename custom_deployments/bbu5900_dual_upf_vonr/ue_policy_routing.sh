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

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: run as root"
    exit 1
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
ExecStart=/bin/sh -c 'ip route replace default via ${N6_GATEWAY} dev ${N6_IF} table ${UE_POLICY_TABLE}; ip rule del from ${UE_IPV4_INTERNET} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip rule del from ${UE_IPV4_IMS} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip rule add from ${UE_IPV4_INTERNET} table ${UE_POLICY_TABLE} priority ${UE_POLICY_PRIO_INTERNET}; ip rule add from ${UE_IPV4_IMS} table ${UE_POLICY_TABLE} priority ${UE_POLICY_PRIO_IMS}; iptables -t nat -C POSTROUTING -s ${UE_IPV4_INTERNET} -o ${N6_IF} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${UE_IPV4_INTERNET} -o ${N6_IF} -j MASQUERADE; iptables -t nat -C POSTROUTING -s ${UE_IPV4_IMS} -o ${N6_IF} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${UE_IPV4_IMS} -o ${N6_IF} -j MASQUERADE'
ExecStop=/bin/sh -c 'iptables -t nat -D POSTROUTING -s ${UE_IPV4_INTERNET} -o ${N6_IF} -j MASQUERADE 2>/dev/null || true; iptables -t nat -D POSTROUTING -s ${UE_IPV4_IMS} -o ${N6_IF} -j MASQUERADE 2>/dev/null || true; ip rule del from ${UE_IPV4_INTERNET} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip rule del from ${UE_IPV4_IMS} table ${UE_POLICY_TABLE} 2>/dev/null || true; ip route del default via ${N6_GATEWAY} dev ${N6_IF} table ${UE_POLICY_TABLE} 2>/dev/null || true'
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

  ip route replace default via "${N6_GATEWAY}" dev "${N6_IF}" table "${UE_POLICY_TABLE}"
  ip rule del from "${UE_IPV4_INTERNET}" table "${UE_POLICY_TABLE}" 2>/dev/null || true
  ip rule del from "${UE_IPV4_IMS}" table "${UE_POLICY_TABLE}" 2>/dev/null || true
  ip rule add from "${UE_IPV4_INTERNET}" table "${UE_POLICY_TABLE}" priority "${UE_POLICY_PRIO_INTERNET}"
  ip rule add from "${UE_IPV4_IMS}" table "${UE_POLICY_TABLE}" priority "${UE_POLICY_PRIO_IMS}"
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
  remove_nat

  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
    systemctl disable --now "${SERVICE_NAME}" 2>/dev/null || true
  fi

  rm -f "${SERVICE_PATH}"
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

  echo "=== Route Decisions ==="
  ip route get 8.8.8.8 from "${UE_IPV4_INTERNET%%/*}" iif "${N6_IF}" 2>/dev/null || true
  ip route get 8.8.8.8 from "${UE_IPV4_IMS%%/*}" iif "${N6_IF}" 2>/dev/null || true

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
