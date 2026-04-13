#!/usr/bin/env bash
set -euo pipefail

# 中文说明：
# - check：仅检查主机环境是否满足部署条件
# - apply：应用推荐内核与挂载设置后再执行检查

MODE="${1:-check}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "错误：缺少命令 $1"
    exit 1
  }
}

check_mount() {
  local target="$1"
  if mountpoint -q "$target"; then
    echo "通过：已挂载 $target"
  else
    echo "警告：未挂载 $target"
  fi
}

check_sysctl() {
  local key="$1"
  local val
  val="$(sysctl -n "$key" 2>/dev/null || true)"
  if [[ -n "$val" ]]; then
    echo "通过：$key=$val"
  else
    echo "警告：无法读取 $key"
  fi
}

apply_settings() {
  echo "开始应用主机设置..."
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  mkdir -p /sys/fs/bpf /sys/kernel/debug
  mountpoint -q /sys/fs/bpf || mount -t bpf bpf /sys/fs/bpf
  mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug

  local scenario_dir
  scenario_dir="$(cd "$(dirname "$0")" && pwd)"
  mkdir -p "$scenario_dir/../../log"

  echo "主机设置应用完成。"
}

main_check() {
  echo "开始执行环境检查..."
  need_cmd docker
  need_cmd sysctl
  need_cmd ip
  need_cmd mountpoint

  echo "通过：docker=$(docker --version | head -n1)"
  if docker compose version >/dev/null 2>&1; then
    echo "通过：$(docker compose version | head -n1)"
  else
    echo "警告：未检测到 docker compose v2"
  fi

  check_sysctl net.ipv4.ip_forward
  check_mount /sys/fs/bpf
  check_mount /sys/kernel/debug

  local scenario_dir
  scenario_dir="$(cd "$(dirname "$0")" && pwd)"
  if [[ -d "$scenario_dir/../../log" ]]; then
    echo "通过：日志目录存在"
  else
    echo "警告：缺少 ../../log 日志目录"
  fi

  echo "环境检查完成。"
}

case "$MODE" in
  check)
    main_check
    ;;
  apply)
    if [[ "${EUID}" -ne 0 ]]; then
      echo "错误：apply 模式必须以 root 运行"
      exit 1
    fi
    apply_settings
    main_check
    ;;
  *)
    echo "用法：$0 [check|apply]"
    exit 1
    ;;
esac
