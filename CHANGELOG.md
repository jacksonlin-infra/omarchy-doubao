# 更新日志

## v0.2.0 — 2026-10-22

边说边出字。按住 F9 时，屏幕底部的悬浮条实时显示识别结果；松开后一秒左右，最终文字打到光标处。

### 新增

- `doubao-dictate`：自己的常驻听写服务，替代 Voxtype。录音、流式识别、悬浮条、上屏都在这一个 Python 脚本里。
- 改用豆包流式接口 `bigmodel_async` 并开启二遍识别：说话时给实时结果，松开后用非流式模型把整段再识别一遍，最终结果和整段识别一样准。
- 屏幕底部悬浮条（GTK4 + gtk4-layer-shell）：显示音量波形、状态和实时文字，配色跟随 Omarchy 主题，不抢键盘焦点。
- 按下时同时开始录音和连接豆包，连上之前录到的音先缓存，开头不丢。
- `doubao.env` 新增参数：`DICTATE_MAX_SECS`（单次上限，默认 300 秒）、`DICTATE_AUDIO_DEVICE`（指定麦克风）、`DICTATE_OUTPUT`（打字 / 只复制 / 只写日志）、`DICTATE_BOTTOM_MARGIN`、`DICTATE_WIDTH`。
- `doubao-dictate selftest`：用 WAV 文件或一秒静音测试鉴权和识别，`check.sh` 用它做检查。
- `DOUBAO_DEBUG=1` 时日志带每一步的时间戳，方便判断慢在本机还是服务端。

### 变化

- 松开后到出字：从约 2.5 秒以上缩短到约 0.7–1 秒（17 秒长句实测；只剩服务端二遍识别的时间）。
- 凭据文件位置：`~/.config/voxtype/doubao.env` → `~/.config/doubao-dictate/doubao.env`。
- 系统包：不再需要 `voxtype-bin`、`ffmpeg`；新增 `python-gobject gtk4 gtk4-layer-shell`（Omarchy 4 已自带）。
- 快捷键：`install.sh` 在 `~/.config/hypr/bindings.lua` 末尾写一段带标记的配置，把 F9 和 Super+Ctrl+X 从 Voxtype 改绑过来；Voxtype 服务被停用（不卸载），`uninstall.sh` 删掉这段配置并重新启用 Voxtype。

### 移除

- `voxtype-doubao-shim` 转接服务、`voxtype-doubao.service`、项目自带的 voxtype `config.toml`。

### 升级

v0.1.0 不能原地升级，先用 v0.1.0 自己的卸载脚本卸掉，再装新版，见 README「从 v0.1.0 升级」。

### 已知限制

- “嗯”“这个”“那个”这类口水词会保留：实测豆包的 `enable_ddc` 去不掉。计划在 v0.3.0 用大模型润色来做。
- Omarchy 3（`bindings.conf`）的快捷键写入没有实测。

## v0.1.0 — 2026-10-22

首个版本：豆包识别作为 Omarchy 自带 Voxtype 的远程识别引擎（OpenAI 兼容转接服务 + `bigmodel_nostream`）。按住 F9 说话，松开后整段识别、打到光标处。
