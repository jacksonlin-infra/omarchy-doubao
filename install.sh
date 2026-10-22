#!/usr/bin/env bash
# Install Doubao (Volcengine) speech recognition as the Voxtype dictation engine on Omarchy.
#
#   ./install.sh                         # prompts for credentials if none are configured yet
#   ./install.sh --api-key KEY           # new Volcengine console
#   ./install.sh --app-id ID --access-token TOKEN   # old Volcengine console
#
# Credentials can also come from the environment (DOUBAO_API_KEY, or DOUBAO_APP_ID and
# DOUBAO_ACCESS_TOKEN). Re-running is safe: existing credentials are kept unless new ones
# are given, and a voxtype config that differs from ours is backed up before replacement.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
VOXTYPE_DIR="$CONFIG_DIR/voxtype"
ENV_FILE="$VOXTYPE_DIR/doubao.env"
UNIT_DIR="$CONFIG_DIR/systemd/user"
BIN_DIR="$HOME/.local/bin"
PACKAGES=(voxtype-bin wtype python-websockets ffmpeg)

API_KEY="${DOUBAO_API_KEY:-}"
APP_ID="${DOUBAO_APP_ID:-}"
ACCESS_TOKEN="${DOUBAO_ACCESS_TOKEN:-}"
RESOURCE_ID="${DOUBAO_RESOURCE_ID:-}"
SKIP_PACKAGES=0
SKIP_SERVICES=0

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m警告:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit "${2:-1}"; }

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --api-key KEY          新版控制台 API Key
  --app-id ID            旧版控制台 App ID（与 --access-token 一起用）
  --access-token TOKEN   旧版控制台 Access Token
  --resource-id ID       默认 volc.seedasr.sauc.duration（模型2.0 按时长）
  --skip-packages        不装系统包（已手动装好时用）
  --skip-services        只放文件，不启动/重启服务、不重载 Hyprland
  -h, --help             显示帮助

Exit codes: 0 成功 · 1 出错 · 3 需要 sudo 密码（脚本会打印要手动执行的命令）
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key) API_KEY="${2:?--api-key 需要参数}"; shift 2 ;;
    --app-id) APP_ID="${2:?--app-id 需要参数}"; shift 2 ;;
    --access-token) ACCESS_TOKEN="${2:?--access-token 需要参数}"; shift 2 ;;
    --resource-id) RESOURCE_ID="${2:?--resource-id 需要参数}"; shift 2 ;;
    --skip-packages) SKIP_PACKAGES=1; shift ;;
    --skip-services) SKIP_SERVICES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $1（--help 查看用法）" ;;
  esac
done

[[ $EUID -ne 0 ]] || die "不要用 root/sudo 运行本脚本；用普通用户运行，需要时脚本自己会调用 sudo"
command -v pacman >/dev/null || die "需要 Arch 系发行版（pacman）。本项目针对 Omarchy。"
if [[ ! -d /usr/share/omarchy && ! -d "$HOME/.local/share/omarchy" ]]; then
  warn "没检测到 Omarchy。voxtype-bin 来自 Omarchy 软件源，F9 快捷键也来自 Omarchy 默认配置；其他系统见 README 的「非 Omarchy」一节。"
fi

# ------------------------------------------------------------ 1. packages ----
install_packages() {
  local missing=()
  for p in "${PACKAGES[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if [[ ${#missing[@]} -eq 0 ]]; then
    say "系统包已齐全：${PACKAGES[*]}"
    return
  fi
  if [[ " ${missing[*]} " == *" voxtype-bin "* ]] && ! pacman -Si voxtype-bin >/dev/null 2>&1; then
    die "软件源里找不到 voxtype-bin。它在 Omarchy 软件源 [omarchy]；非 Omarchy 系统请先按 https://voxtype.io 安装 voxtype，再用 --skip-packages 重跑。"
  fi
  local cmd=(sudo pacman -S --needed --noconfirm "${missing[@]}")
  if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
    say "安装系统包：${missing[*]}"
    "${cmd[@]}"
  else
    printf '\n需要 sudo 密码才能装系统包。请在终端里手动执行下面这条命令，然后重新运行 ./install.sh：\n\n  %s\n\n' "${cmd[*]}" >&2
    exit 3
  fi
}
[[ $SKIP_PACKAGES -eq 1 ]] && say "跳过系统包安装（--skip-packages）" || install_packages

for c in voxtype wtype ffmpeg python3; do command -v "$c" >/dev/null || die "缺少命令 $c"; done
python3 -c 'import websockets.sync.client' 2>/dev/null || die "Python 缺少 websockets（pacman -S python-websockets）"

# --------------------------------------------------------------- 2. shim ----
say "安装转接服务 → $BIN_DIR/voxtype-doubao-shim"
install -Dm755 "$REPO_DIR/bin/voxtype-doubao-shim" "$BIN_DIR/voxtype-doubao-shim"

# -------------------------------------------------------- 3. credentials ----
mkdir -p "$VOXTYPE_DIR"
if [[ ! -f "$ENV_FILE" ]]; then
  say "创建凭据文件 $ENV_FILE"
  install -m600 "$REPO_DIR/config/doubao.env.example" "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"

# Set KEY=VALUE in the env file without echoing secrets or tripping over special characters.
set_env() {
  python3 - "$ENV_FILE" "$1" "$2" <<'PY'
import sys, re
path, key, val = sys.argv[1:4]
lines = open(path, encoding="utf-8").read().splitlines()
pat = re.compile(rf"^\s*{re.escape(key)}\s*=")
for i, line in enumerate(lines):
    if pat.match(line):
        lines[i] = f"{key}={val}"
        break
else:
    lines.append(f"{key}={val}")
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
}
env_value() {
  python3 - "$ENV_FILE" "$1" <<'PY'
import sys
path, key = sys.argv[1:3]
val = ""
for line in open(path, encoding="utf-8"):
    k, sep, v = line.strip().partition("=")
    if sep and k.strip() == key:
        val = v.strip().strip('"').strip("'")
print(val)
PY
}

has_creds() { [[ -n "$(env_value DOUBAO_API_KEY)" ]] || { [[ -n "$(env_value DOUBAO_APP_ID)" ]] && [[ -n "$(env_value DOUBAO_ACCESS_TOKEN)" ]]; }; }

if [[ -z "$API_KEY$APP_ID$ACCESS_TOKEN" ]] && ! has_creds && [[ -t 0 ]]; then
  echo
  echo "还没有豆包凭据。新版控制台填 API Key；旧版控制台直接回车，再填 App ID 和 Access Token。"
  read -rsp "API Key（输入不回显）: " API_KEY; echo
  if [[ -z "$API_KEY" ]]; then
    read -rp  "App ID: " APP_ID
    read -rsp "Access Token（输入不回显）: " ACCESS_TOKEN; echo
  fi
fi

if [[ -n "$API_KEY" ]]; then
  set_env DOUBAO_API_KEY "$API_KEY"
  say "已写入 API Key（新版控制台）"
elif [[ -n "$APP_ID$ACCESS_TOKEN" ]]; then
  [[ -n "$APP_ID" && -n "$ACCESS_TOKEN" ]] || die "旧版控制台需要同时提供 App ID 和 Access Token"
  set_env DOUBAO_APP_ID "$APP_ID"
  set_env DOUBAO_ACCESS_TOKEN "$ACCESS_TOKEN"
  say "已写入 App ID + Access Token（旧版控制台）"
fi
[[ -n "$RESOURCE_ID" ]] && set_env DOUBAO_RESOURCE_ID "$RESOURCE_ID"
has_creds || warn "凭据仍为空：编辑 $ENV_FILE 填好后执行 systemctl --user restart voxtype-doubao"

# ----------------------------------------------------- 4. voxtype config ----
target="$VOXTYPE_DIR/config.toml"
if [[ -f "$target" ]] && ! cmp -s "$target" "$REPO_DIR/config/voxtype-config.toml"; then
  backup="$target.bak.$(date +%Y%m%d-%H%M%S)"
  cp -p "$target" "$backup"
  say "已备份原 voxtype 配置 → $backup"
fi
install -m644 "$REPO_DIR/config/voxtype-config.toml" "$target"
say "写入 voxtype 配置 → $target（remote 模式，指向 127.0.0.1:6688）"

port="$(env_value SHIM_PORT)"; port="${port:-6688}"
if [[ "$port" != "6688" ]]; then
  sed -i "s#^remote_endpoint = .*#remote_endpoint = \"http://127.0.0.1:$port\"#" "$target"
fi

# ----------------------------------------------------------- 5. services ----
install -Dm644 "$REPO_DIR/systemd/voxtype-doubao.service" "$UNIT_DIR/voxtype-doubao.service"

if [[ $SKIP_SERVICES -eq 1 ]]; then
  say "跳过服务启动（--skip-services）"
  exit 0
fi

systemctl --user daemon-reload
systemctl --user enable voxtype-doubao.service >/dev/null 2>&1
systemctl --user restart voxtype-doubao.service
say "已启动 voxtype-doubao（转接服务，开机自启）"

# voxtype's own user unit: same command Omarchy's omarchy-voxtype-install uses.
if [[ ! -f "$UNIT_DIR/voxtype.service" ]]; then
  voxtype setup systemd >/dev/null
fi
systemctl --user daemon-reload
systemctl --user enable voxtype.service >/dev/null 2>&1
systemctl --user restart voxtype.service
say "已重启 voxtype（读取新配置）"

# Omarchy only binds F9 / Super+Ctrl+X when voxtype is present at config load time.
# Over SSH the Hyprland instance variable is unset; pick it up when exactly one is running.
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -d "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" ]]; then
  mapfile -t instances < <(ls -1 "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr")
  [[ ${#instances[@]} -eq 1 ]] && export HYPRLAND_INSTANCE_SIGNATURE="${instances[0]}"
fi
if command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1; then
  say "已重载 Hyprland 快捷键（F9 按住说话，Super+Ctrl+X 开关式）"
  command -v omarchy-restart-shell >/dev/null && omarchy-restart-shell >/dev/null 2>&1 || true
else
  warn "没能重载 Hyprland（不在桌面会话里运行？）。回到桌面执行一次 hyprctl reload，或注销重登，F9 才会生效。"
fi

# -------------------------------------------------------------- 6. check ----
echo
"$REPO_DIR/check.sh" || exit 1
