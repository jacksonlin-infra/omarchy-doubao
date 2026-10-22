#!/usr/bin/env bash
# Verify the Doubao + Voxtype dictation setup, step by step.
#
#   ./check.sh               # everything except a real-speech test
#   ./check.sh speech.wav    # also transcribe a recording end to end through voxtype
#
# Never prints credentials. Exit code 0 only when every check passes.

set -uo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
ENV_FILE="$CONFIG_DIR/voxtype/doubao.env"
VOX_CONFIG="$CONFIG_DIR/voxtype/config.toml"
SHIM="$HOME/.local/bin/voxtype-doubao-shim"
fails=0

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; fails=$((fails + 1)); }
info() { printf '  \033[1;33m!\033[0m %s\n' "$*"; }

env_value() {
  [[ -f "$ENV_FILE" ]] || return 0
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

echo "检查豆包语音输入配置："

for p in voxtype-bin wtype python-websockets ffmpeg; do
  pacman -Q "$p" >/dev/null 2>&1 && ok "已安装 $p" || bad "缺少系统包 $p（sudo pacman -S --needed $p）"
done

[[ -x "$SHIM" ]] && ok "转接服务脚本 $SHIM" || bad "缺少 $SHIM（运行 ./install.sh）"

if [[ -f "$ENV_FILE" ]]; then
  perm="$(stat -c %a "$ENV_FILE")"
  [[ "$perm" == "600" ]] && ok "凭据文件权限 600" || info "凭据文件权限是 $perm，建议 chmod 600 $ENV_FILE"
  if [[ -n "$(env_value DOUBAO_API_KEY)" ]]; then
    ok "凭据：API Key（新版控制台）"
  elif [[ -n "$(env_value DOUBAO_APP_ID)" && -n "$(env_value DOUBAO_ACCESS_TOKEN)" ]]; then
    ok "凭据：App ID + Access Token（旧版控制台）"
  else
    bad "凭据为空：编辑 $ENV_FILE"
  fi
  rid="$(env_value DOUBAO_RESOURCE_ID)"
  ok "资源 ID：${rid:-volc.seedasr.sauc.duration（默认）}"
else
  bad "缺少凭据文件 $ENV_FILE"
fi

port="$(env_value SHIM_PORT)"; port="${port:-6688}"
if [[ -f "$VOX_CONFIG" ]]; then
  grep -qE '^mode = "remote"' "$VOX_CONFIG" && ok "voxtype 使用 remote 模式" || bad "voxtype 不是 remote 模式（$VOX_CONFIG 的 [whisper] mode）"
  grep -qE "^remote_endpoint = \"http://127.0.0.1:$port\"" "$VOX_CONFIG" \
    && ok "voxtype 指向 127.0.0.1:$port" || bad "voxtype 的 remote_endpoint 没指向 http://127.0.0.1:$port"
  grep -qE '^driver_order = \["wtype"' "$VOX_CONFIG" && ok "打字驱动 wtype 优先（中文必需）" || bad "driver_order 没把 wtype 放第一位，中文会打不出来"
else
  bad "缺少 voxtype 配置 $VOX_CONFIG"
fi

for unit in voxtype-doubao voxtype; do
  if systemctl --user is-active --quiet "$unit"; then ok "服务 $unit 运行中"
  else bad "服务 $unit 没在运行（journalctl --user -u $unit -n 30）"; fi
  systemctl --user is-enabled --quiet "$unit" 2>/dev/null || info "服务 $unit 未设开机自启（systemctl --user enable $unit）"
done

if python3 -c "import urllib.request,sys; urllib.request.urlopen('http://127.0.0.1:$port/health', timeout=3)" 2>/dev/null; then
  ok "转接服务健康检查 http://127.0.0.1:$port/health"
else
  bad "转接服务没响应 127.0.0.1:$port"
fi

# Auth check: one second of silence must get through the Doubao handshake.
if [[ -x "$SHIM" ]]; then
  tmp="$(mktemp --suffix=.wav)"
  ffmpeg -loglevel error -f lavfi -i anullsrc=r=16000:cl=mono -t 1 -y "$tmp"
  if err="$("$SHIM" --selftest "$tmp" 2>&1 >/dev/null)"; then
    ok "豆包鉴权通过（建连 + 识别请求正常）"
  else
    bad "豆包鉴权失败：$(printf '%s' "$err" | tail -1)"
  fi
  rm -f "$tmp"
fi

if [[ $# -ge 1 ]]; then
  # voxtype prints progress lines on stdout before the transcript; keep the last line.
  if text="$(timeout 60 voxtype -q transcribe "$1" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -1)" && [[ -n "$text" ]]; then
    ok "端到端识别：$text"
  else
    bad "端到端识别失败（voxtype transcribe $1）"
  fi
fi

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -d "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" ]]; then
  mapfile -t instances < <(ls -1 "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr")
  [[ ${#instances[@]} -eq 1 ]] && export HYPRLAND_INSTANCE_SIGNATURE="${instances[0]}"
fi
if command -v hyprctl >/dev/null && binds="$(hyprctl binds -j 2>/dev/null)" && [[ -n "$binds" ]]; then
  # Omarchy 4 binds through Lua, so the dispatcher arg is an id; match on key + description too.
  if python3 -c '
import json, sys
binds = json.load(sys.stdin)
sys.exit(0 if any(
    b.get("key") == "F9" and (
        "dictation" in (b.get("description") or "").lower()
        or "voxtype" in (b.get("arg") or ""))
    for b in binds) else 1)' <<<"$binds"; then
    ok "Hyprland 已绑定 F9（按住说话）"
  else
    bad "Hyprland 里没有 F9 听写快捷键：执行 hyprctl reload，或注销重登"
  fi
else
  info "不在 Hyprland 会话里，跳过快捷键检查"
fi

echo
if [[ $fails -eq 0 ]]; then
  echo "全部通过。按住 F9 说话，松开后文字会打到光标处。"
else
  echo "$fails 项未通过，按上面的提示处理后重新运行 ./check.sh"
  exit 1
fi
