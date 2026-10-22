#!/usr/bin/env bash
# Remove Doubao dictation and hand F9 back to voxtype.
#
#   ./uninstall.sh           # keeps ~/.config/doubao-dictate/doubao.env (your credentials)
#   ./uninstall.sh --purge   # also deletes the credentials file
#
# Voxtype itself was never removed: it belongs to Omarchy. If install.sh switched
# its service off, it is switched back on here.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-doubao"
UNIT_DIR="$CONFIG_DIR/systemd/user"
HYPR_DIR="$CONFIG_DIR/hypr"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

systemctl --user disable --now doubao-dictate.service 2>/dev/null || true
rm -f "$UNIT_DIR/doubao-dictate.service" "$HOME/.local/bin/doubao-dictate" \
      "${XDG_RUNTIME_DIR:-/run/user/$UID}/doubao-dictate.sock"
systemctl --user daemon-reload
say "已移除听写服务 doubao-dictate"

for f in "$HYPR_DIR/bindings.lua" "$HYPR_DIR/bindings.conf"; do
  [[ -f "$f" ]] || continue
  python3 - "$f" <<'PY'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
out, skipping, found = [], False, False
for line in lines:
    s = line.strip()
    if s.endswith(">>> omarchy-doubao: managed by install.sh, removed by uninstall.sh >>>"):
        skipping = found = True
    elif skipping and s.endswith("<<< omarchy-doubao <<<"):
        skipping = False
    elif not skipping:
        out.append(line)
if found:
    while out and not out[-1].strip():
        out.pop()
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(path)
PY
done | while read -r f; do say "已从 $f 移除快捷键"; done

if [[ -f "$STATE_DIR/voxtype-was-enabled" ]]; then
  systemctl --user enable --now voxtype.service >/dev/null 2>&1 || true
  rm -f "$STATE_DIR/voxtype-was-enabled"
  say "已重新启用 voxtype 服务"
fi
rmdir "$STATE_DIR" 2>/dev/null || true

if [[ $PURGE -eq 1 ]]; then
  rm -f "$CONFIG_DIR/doubao-dictate/doubao.env"
  rmdir "$CONFIG_DIR/doubao-dictate" 2>/dev/null || true
  say "已删除凭据文件 doubao.env"
fi

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -d "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr" ]]; then
  mapfile -t instances < <(ls -1 "${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr")
  [[ ${#instances[@]} -eq 1 ]] && export HYPRLAND_INSTANCE_SIGNATURE="${instances[0]}"
fi
command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 && say "已重载 Hyprland 快捷键（F9 回到 voxtype）"
say "完成"
