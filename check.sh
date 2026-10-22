#!/usr/bin/env bash
# Verify the Doubao streaming dictation setup, step by step.
#
#   ./check.sh               # everything except a real-speech test
#   ./check.sh speech.wav    # also stream a 16 kHz mono WAV through Doubao and print the text
#
# Never prints credentials. Exit code 0 only when every check passes.

set -uo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
ENV_FILE="$CONFIG_DIR/doubao-dictate/doubao.env"
BIN="$HOME/.local/bin/doubao-dictate"
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

for p in wtype wl-clipboard libnotify pipewire python-websockets python-gobject gtk4 gtk4-layer-shell; do
  pacman -Q "$p" >/dev/null 2>&1 && ok "已安装 $p" || bad "缺少系统包 $p（sudo pacman -S --needed $p）"
done

[[ -x "$BIN" ]] && ok "听写服务程序 $BIN（v$("$BIN" --version)）" || bad "缺少 $BIN（运行 ./install.sh）"
[[ -e "$HOME/.local/bin/voxtype-doubao-shim" ]] \
  && bad "还留着 v0.1.0 的转接服务：git show v0.1.0:uninstall.sh | bash -s -- --purge，然后重跑 ./install.sh"

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
  endpoint="$(env_value DOUBAO_ENDPOINT)"
  case "$endpoint" in
    ""|*/bigmodel_async) ok "识别端点：流式 bigmodel_async（边说边出字 + 二遍识别）" ;;
    *) bad "识别端点 $endpoint 不是 .../sauc/bigmodel_async，说话时不会实时出字" ;;
  esac
else
  bad "缺少凭据文件 $ENV_FILE"
fi

if systemctl --user is-active --quiet doubao-dictate; then ok "服务 doubao-dictate 运行中"
else bad "服务 doubao-dictate 没在运行（journalctl --user -u doubao-dictate -n 30）"; fi
systemctl --user is-enabled --quiet doubao-dictate 2>/dev/null || info "服务 doubao-dictate 未设自启（systemctl --user enable doubao-dictate）"

if [[ -x "$BIN" ]] && state="$("$BIN" status 2>/dev/null)"; then
  ok "服务响应控制命令（当前状态：$state）"
else
  bad "服务没响应控制命令（journalctl --user -u doubao-dictate -n 30）"
fi

if systemctl --user is-active --quiet voxtype 2>/dev/null; then
  bad "voxtype 服务还在运行，会和 F9 抢麦克风（systemctl --user disable --now voxtype）"
else
  ok "voxtype 服务已停用"
fi

# Auth check: one second of silence must get through the Doubao handshake.
if [[ -x "$BIN" ]]; then
  if err="$("$BIN" selftest --silence 2>&1 >/dev/null)"; then
    ok "豆包鉴权通过（建连 + 流式识别请求正常）"
  else
    bad "豆包鉴权失败：$(printf '%s' "$err" | tail -1)"
  fi
fi

if [[ $# -ge 1 && -x "$BIN" ]]; then
  if text="$("$BIN" selftest "$1" 2>/dev/null)" && [[ -n "$text" ]]; then
    ok "端到端识别：$text"
  else
    bad "端到端识别失败（$BIN selftest $1）"
  fi
fi

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -d "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" ]]; then
  mapfile -t instances < <(ls -1 "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr")
  [[ ${#instances[@]} -eq 1 ]] && export HYPRLAND_INSTANCE_SIGNATURE="${instances[0]}"
fi
if command -v hyprctl >/dev/null && binds="$(hyprctl binds -j 2>/dev/null)" && [[ -n "$binds" ]]; then
  # Omarchy 4 binds through Lua, so the dispatcher arg is an id; match on the description too.
  if python3 -c '
import json, sys
binds = json.load(sys.stdin)
f9 = [b for b in binds if b.get("key") == "F9" and not b.get("modmask")]
ours = lambda b: "doubao" in ((b.get("description") or "") + (b.get("arg") or "")).lower()
press = [b for b in f9 if not b.get("release")]
release = [b for b in f9 if b.get("release")]
sys.exit(0 if press and release and all(map(ours, press + release)) else 1)' <<<"$binds"; then
    ok "Hyprland 已把 F9 绑定到豆包听写（按住说话）"
  else
    bad "Hyprland 的 F9 没有绑定到 doubao-dictate：重跑 ./install.sh，或执行 hyprctl reload / 注销重登"
  fi
else
  info "不在 Hyprland 会话里，跳过快捷键检查"
fi

echo
if [[ $fails -eq 0 ]]; then
  echo "全部通过。按住 F9 说话，屏幕底部实时出字，松开后文字打到光标处。"
else
  echo "$fails 项未通过，按上面的提示处理后重新运行 ./check.sh"
  exit 1
fi
