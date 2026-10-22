#!/usr/bin/env bash
# Install Doubao (Volcengine) streaming dictation on Omarchy: hold F9 and speak,
# live text shows in a bar at the bottom of the screen, release to type it.
#
#   ./install.sh                         # prompts for credentials if none are configured yet
#   ./install.sh --api-key KEY           # new Volcengine console
#   ./install.sh --app-id ID --access-token TOKEN   # old Volcengine console
#
# Credentials can also come from the environment (DOUBAO_API_KEY, or DOUBAO_APP_ID and
# DOUBAO_ACCESS_TOKEN). Re-running is safe: existing credentials are kept unless new ones
# are given. Voxtype is switched off (not removed); ./uninstall.sh switches it back on.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-doubao"
ENV_DIR="$CONFIG_DIR/doubao-dictate"
ENV_FILE="$ENV_DIR/doubao.env"
UNIT_DIR="$CONFIG_DIR/systemd/user"
BIN_DIR="$HOME/.local/bin"
HYPR_DIR="$CONFIG_DIR/hypr"
PACKAGES=(wtype wl-clipboard libnotify pipewire python-websockets python-gobject gtk4 gtk4-layer-shell)

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
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --api-key KEY          新版控制台 API Key
  --app-id ID            旧版控制台 App ID（与 --access-token 一起用）
  --access-token TOKEN   旧版控制台 Access Token
  --resource-id ID       默认 volc.seedasr.sauc.duration（模型2.0 按时长）
  --skip-packages        不装系统包（已手动装好时用）
  --skip-services        只放文件，不启动/重启服务、不改快捷键
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
if [[ -e "$BIN_DIR/voxtype-doubao-shim" ]]; then
  die "检测到 v0.1.0（voxtype + 转接服务）。先在本仓库目录执行 git fetch --tags && git show v0.1.0:uninstall.sh | bash -s -- --purge 卸掉旧版，再重新运行 ./install.sh（见 README「从 v0.1.0 升级」）"
fi
if [[ ! -d /usr/share/omarchy && ! -d "$HOME/.local/share/omarchy" ]]; then
  warn "没检测到 Omarchy。F9 快捷键会写进 Omarchy 的 Hyprland 配置；其他系统见 README 的「非 Omarchy」一节。"
fi

# ------------------------------------------------------------ 1. packages ----
install_packages() {
  local missing=()
  for p in "${PACKAGES[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if [[ ${#missing[@]} -eq 0 ]]; then
    say "系统包已齐全：${PACKAGES[*]}"
    return
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

for c in wtype pw-record python3; do command -v "$c" >/dev/null || die "缺少命令 $c"; done
python3 -c 'import websockets.sync.client' 2>/dev/null || die "Python 缺少 websockets（pacman -S python-websockets）"
python3 -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("Gtk4LayerShell", "1.0")' 2>/dev/null \
  || die "Python 缺少 GTK4 / gtk4-layer-shell 绑定（pacman -S python-gobject gtk4 gtk4-layer-shell）"

# -------------------------------------------------------------- 2. daemon ----
say "安装听写服务 v$(python3 "$REPO_DIR/bin/doubao-dictate" --version) → $BIN_DIR/doubao-dictate"
install -Dm755 "$REPO_DIR/bin/doubao-dictate" "$BIN_DIR/doubao-dictate"

# -------------------------------------------------------- 3. credentials ----
mkdir -p "$ENV_DIR"
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
has_creds || warn "凭据仍为空：编辑 $ENV_FILE 填好后执行 systemctl --user restart doubao-dictate"

if [[ $SKIP_SERVICES -eq 1 ]]; then
  install -Dm644 "$REPO_DIR/systemd/doubao-dictate.service" "$UNIT_DIR/doubao-dictate.service"
  say "跳过服务启动和快捷键（--skip-services）"
  exit 0
fi

# ------------------------------------------------------ 4. voxtype off ----
# Both would grab the microphone on F9. Remember voxtype was on so uninstall can turn it back on.
if systemctl --user is-enabled --quiet voxtype.service 2>/dev/null \
   || systemctl --user is-active --quiet voxtype.service 2>/dev/null; then
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/voxtype-was-enabled"
  systemctl --user disable --now voxtype.service >/dev/null 2>&1 || true
  say "已停用 voxtype 服务（没有卸载；./uninstall.sh 会重新启用）"
fi

# ------------------------------------------------------------- 5. hotkeys ----
# Omarchy binds F9 / Super+Ctrl+X to voxtype whenever voxtype is installed.
# A marked block in the user's own bindings file rebinds them to us.
write_bindings() {
  python3 - "$1" "$2" <<'PY'
import sys
path, kind = sys.argv[1:3]
c = "--" if kind == "lua" else "#"
begin = f"{c} >>> omarchy-doubao: managed by install.sh, removed by uninstall.sh >>>"
end = f"{c} <<< omarchy-doubao <<<"
if kind == "lua":
    body = [
        "-- Doubao streaming dictation takes over F9 / Super+Ctrl+X from voxtype.",
        "-- pcall: unbinding a key that is not bound must not break the rest of this file.",
        'pcall(hl.unbind, "F9")',
        'pcall(hl.unbind, "SUPER + CTRL + X")',
        'o.bind("F9", "Doubao dictation start (push-to-talk)", "doubao-dictate start")',
        'o.bind("F9", "Doubao dictation stop (push-to-talk)", "doubao-dictate stop", { release = true })',
        'o.bind("SUPER + CTRL + X", "Doubao dictation toggle", "doubao-dictate toggle")',
    ]
else:
    body = [
        "# Doubao streaming dictation takes over F9 / Super+Ctrl+X from voxtype.",
        "unbind = , F9",
        "unbind = SUPER CTRL, X",
        "bindd = , F9, Doubao dictation start (push-to-talk), exec, doubao-dictate start",
        "bindrd = , F9, Doubao dictation stop (push-to-talk), exec, doubao-dictate stop",
        "bindd = SUPER CTRL, X, Doubao dictation toggle, exec, doubao-dictate toggle",
    ]
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except FileNotFoundError:
    lines = []
out, skipping = [], False
for line in lines:
    if line.strip() == begin:
        skipping = True
    elif skipping and line.strip() == end:
        skipping = False
    elif not skipping:
        out.append(line)
while out and not out[-1].strip():
    out.pop()
out += ["", begin, *body, end]
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
}

if [[ -f "$HYPR_DIR/bindings.lua" ]]; then
  write_bindings "$HYPR_DIR/bindings.lua" lua
  say "快捷键已写入 $HYPR_DIR/bindings.lua（F9 按住说话，Super+Ctrl+X 开关式）"
elif [[ -f "$HYPR_DIR/bindings.conf" ]]; then
  write_bindings "$HYPR_DIR/bindings.conf" conf
  say "快捷键已写入 $HYPR_DIR/bindings.conf（F9 按住说话，Super+Ctrl+X 开关式）"
else
  warn "没找到 $HYPR_DIR/bindings.lua 或 bindings.conf，快捷键需要手动添加（见 README「非 Omarchy」）"
fi

# ----------------------------------------------------------- 6. service ----
install -Dm644 "$REPO_DIR/systemd/doubao-dictate.service" "$UNIT_DIR/doubao-dictate.service"
systemctl --user daemon-reload
systemctl --user enable doubao-dictate.service >/dev/null 2>&1
systemctl --user restart doubao-dictate.service
say "已启动 doubao-dictate（随桌面会话自启）"

# Over SSH the Hyprland instance variable is unset; pick it up when exactly one is running.
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -d "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" ]]; then
  mapfile -t instances < <(ls -1 "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr")
  [[ ${#instances[@]} -eq 1 ]] && export HYPRLAND_INSTANCE_SIGNATURE="${instances[0]}"
fi
if command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1; then
  say "已重载 Hyprland 快捷键"
else
  warn "没能重载 Hyprland（不在桌面会话里运行？）。回到桌面执行一次 hyprctl reload，或注销重登，F9 才会生效。"
fi

# -------------------------------------------------------------- 7. check ----
echo
# Give the freshly restarted service a moment to open its control socket.
sleep 1
"$REPO_DIR/check.sh" || exit 1
