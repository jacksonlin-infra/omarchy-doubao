#!/usr/bin/env bash
# Remove the Doubao bridge and put voxtype back on its previous config.
#
#   ./uninstall.sh           # keeps ~/.config/voxtype/doubao.env (your credentials)
#   ./uninstall.sh --purge   # also deletes the credentials file
#
# Voxtype itself stays installed: it belongs to Omarchy. Remove it with
# omarchy-voxtype-remove (or Omarchy menu → Remove → Dictation) if you want it gone.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
VOXTYPE_DIR="$CONFIG_DIR/voxtype"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

systemctl --user disable --now voxtype-doubao.service 2>/dev/null || true
rm -f "$CONFIG_DIR/systemd/user/voxtype-doubao.service" "$HOME/.local/bin/voxtype-doubao-shim"
systemctl --user daemon-reload
say "已移除转接服务 voxtype-doubao"

latest_backup="$(ls -1t "$VOXTYPE_DIR"/config.toml.bak.* 2>/dev/null | head -1 || true)"
if [[ -n "$latest_backup" ]]; then
  cp -p "$latest_backup" "$VOXTYPE_DIR/config.toml"
  say "已恢复 voxtype 配置 ← $latest_backup"
elif [[ -f /usr/share/omarchy/default/voxtype/config.toml ]]; then
  cp /usr/share/omarchy/default/voxtype/config.toml "$VOXTYPE_DIR/config.toml"
  say "已恢复 Omarchy 默认 voxtype 配置（本地 Whisper，需要 voxtype setup --download 下载模型）"
fi

if [[ $PURGE -eq 1 ]]; then
  rm -f "$VOXTYPE_DIR/doubao.env"
  say "已删除凭据文件 doubao.env"
fi

systemctl --user restart voxtype.service 2>/dev/null || true
say "完成"
