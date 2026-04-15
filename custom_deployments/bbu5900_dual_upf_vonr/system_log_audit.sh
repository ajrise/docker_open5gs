#!/usr/bin/env bash
# 统一日志审计脚本：汇总所有网元日志，检查异常报错、用户面告警、重连恢复、终端离线、PCO兼容性与 IMS 呼叫异常
# 用法:
#   bash system_log_audit.sh                 # 默认检查最近30分钟
#   bash system_log_audit.sh 60             # 检查最近60分钟
#   bash system_log_audit.sh 2h /tmp/audit  # 检查最近2小时，输出到指定目录

set -uo pipefail

normalize_since() {
    local value="${1:-30m}"
    case "$value" in
        *s|*m|*h|*d) echo "$value" ;;
        *) echo "${value}m" ;;
    esac
}

SINCE="$(normalize_since "${1:-30m}")"
OUTDIR="${2:-/tmp/open5gs_log_audit_$(date +%Y%m%d_%H%M%S)}"
RAW_DIR="$OUTDIR/raw"
mkdir -p "$RAW_DIR"

CONTAINERS=(
    mongo webui nrf scp ausf udr udm smf eupf upf amf pcf bsf nssf
    dns mysql pyhss icscf scscf pcscf rtpengine smsc metrics grafana
)

ERROR_RE='ERROR|FATAL|PANIC|CRITICAL|Traceback|assert|create_sm_context failed|PFCP.*failed|Send Error Indication|Error Indication from gNB|Invalid GTPU Type|connection refused|No PSTN-Gateways available|Failed'
USERPLANE_RE='Error Indication from gNB|Send Error Indication|Invalid GTPU Type|No Session|Not found|Removed Session|UE is being triggering Service Request'
PCO_RE='Unknown PCO ID'
RECONNECT_RE='Registration complete|InitialUEMessage|Service Request|Echo Request|Echo Response|association|accepted|Setup NF EndPoint|Session Establishment Request|Session Modification Request|Session Deletion Request|reconnect|re-established'
UE_RE='Deregistration request|UE Context Release|Release SM context|Removed] Number of gNB-UEs|DUPLICATED_PDU_SESSION_ID|N2 transfer message duplicated|offline|detach|deregister|N2-RELEASED'
IMS_RE='INVITE|100 Trying|180 Ringing|183 Session Progress|200 OK|486|487|403|404|408|480|500|503|BYE|CANCEL|PRACK'

section() {
    echo
    echo "==== $1 ===="
}

write_host_snapshot() {
    {
        echo "Audit time: $(date)"
        echo "Since: $SINCE"
        echo
        echo "[docker ps -a]"
        docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
        echo
        echo "[routing]"
        ip rule show 2>/dev/null || true
        echo
        ip route show 2>/dev/null || true
        echo
        echo "[udp listeners]"
        ss -lunp 2>/dev/null | grep -E ':2152|:8805|:38412|:5060|:6060|:7777|:9091|:9090' || true
    } > "$OUTDIR/host_snapshot.txt" 2>&1
}

collect_logs() {
    local c="$1"
    local raw="$RAW_DIR/${c}.log"

    if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
        docker logs --since "$SINCE" "$c" > "$raw" 2>&1 || true
    else
        echo "[container missing] $c" > "$raw"
    fi

    grep -Ein "$ERROR_RE" "$raw" > "$OUTDIR/${c}_errors.log" 2>/dev/null || true
    grep -Ein "$USERPLANE_RE" "$raw" > "$OUTDIR/${c}_userplane.log" 2>/dev/null || true
    grep -Ein "$PCO_RE" "$raw" > "$OUTDIR/${c}_pco.log" 2>/dev/null || true
    grep -Ein "$RECONNECT_RE" "$raw" > "$OUTDIR/${c}_reconnect.log" 2>/dev/null || true
    grep -Ein "$UE_RE" "$raw" > "$OUTDIR/${c}_ue_state.log" 2>/dev/null || true
    grep -Ein "$IMS_RE" "$raw" > "$OUTDIR/${c}_ims.log" 2>/dev/null || true
}

build_summary() {
    local summary="$OUTDIR/summary.txt"
    {
        echo "Open5GS / IMS log audit summary"
        echo "Generated at: $(date)"
        echo "Time window: last $SINCE"
        echo
        printf '%-12s %-8s %-8s %-11s %-10s %-10s %-8s %-6s\n' 'Container' 'Exists' 'Errors' 'UserPlane' 'Reconnect' 'UE-State' 'IMS' 'PCO'
        printf '%-12s %-8s %-8s %-11s %-10s %-10s %-8s %-6s\n' '---------' '------' '------' '---------' '---------' '--------' '---' '---'

        for c in "${CONTAINERS[@]}"; do
            local raw="$RAW_DIR/${c}.log"
            local exists="no"
            local err_count="0"
            local userplane_count="0"
            local reconn_count="0"
            local ue_count="0"
            local ims_count="0"
            local pco_count="0"

            if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
                exists="yes"
            fi

            err_count=$(grep -Eic "$ERROR_RE" "$raw" 2>/dev/null || true)
            userplane_count=$(grep -Eic "$USERPLANE_RE" "$raw" 2>/dev/null || true)
            reconn_count=$(grep -Eic "$RECONNECT_RE" "$raw" 2>/dev/null || true)
            ue_count=$(grep -Eic "$UE_RE" "$raw" 2>/dev/null || true)
            ims_count=$(grep -Eic "$IMS_RE" "$raw" 2>/dev/null || true)
            pco_count=$(grep -Eic "$PCO_RE" "$raw" 2>/dev/null || true)

            printf '%-12s %-8s %-8s %-11s %-10s %-10s %-8s %-6s\n' "$c" "$exists" "$err_count" "$userplane_count" "$reconn_count" "$ue_count" "$ims_count" "$pco_count"
        done

        echo
        echo "Important event patterns"
        echo "- UserPlane/GTP: Error Indication from gNB, Send Error Indication, Invalid GTPU Type, No Session, Removed Session"
        echo "- UE state: Deregistration request, UE Context Release, DUPLICATED_PDU_SESSION_ID, N2-RELEASED"
        echo "- Reconnect/recovery: InitialUEMessage, Registration complete, Service Request, Session Establishment/Deletion"
        echo "- PCO compatibility: Unknown PCO ID (usually low severity, but worth tracking by UE type)"
        echo "- IMS call: INVITE, Trying, Ringing, 200 OK, BYE, CANCEL, 4xx/5xx"

        echo
        echo "Interpretation hints"
        echo "- Repeated 'Error Indication from gNB' on ims should be correlated with idle/release and bearer recovery windows."
        echo "- 'Unknown PCO ID' is often a UE compatibility warning rather than a fatal core-network fault."
    } > "$summary"
}

build_timeline() {
    local timeline="$OUTDIR/important_timeline.log"
    : > "$timeline"

    for c in "${CONTAINERS[@]}"; do
        local raw="$RAW_DIR/${c}.log"
        if [ -f "$raw" ]; then
            grep -Ein "$ERROR_RE|$USERPLANE_RE|$PCO_RE|$RECONNECT_RE|$UE_RE|$IMS_RE" "$raw" 2>/dev/null | sed "s#^#[$c] #" >> "$timeline" || true
        fi
    done
}

print_console_digest() {
    section "Audit complete"
    echo "Output directory: $OUTDIR"
    echo "Summary file: $OUTDIR/summary.txt"
    echo "Timeline file: $OUTDIR/important_timeline.log"

    section "Summary preview"
    sed -n '1,80p' "$OUTDIR/summary.txt"

    section "Important events preview"
    if [ -s "$OUTDIR/important_timeline.log" ]; then
        tail -n 120 "$OUTDIR/important_timeline.log"
    else
        echo "No matching key events were found in the last $SINCE."
    fi
}

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker command not found. Run this script on the deployment host." >&2
    exit 1
fi

write_host_snapshot

for c in "${CONTAINERS[@]}"; do
    collect_logs "$c"
done

build_summary
build_timeline
print_console_digest
