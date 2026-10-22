# omarchy-doubao

在 [Omarchy](https://omarchy.org) 上用**豆包语音识别**做语音输入：按住 **F9** 说话，屏幕底部的悬浮条**边说边出字**，松开后一秒左右，带标点的中文打到光标处。浏览器、终端、编辑器、Claude Code / Codex 的输入框都能用。

豆包输入法没有 Linux 版，但它背后的识别引擎（火山引擎「豆包流式语音识别大模型」）开放了 API。本仓库用它的流式接口做了一个常驻服务，本机不跑任何模型。

当前版本 **v0.2.0**，改动见 [CHANGELOG](CHANGELOG.md)。用过 v0.1.0 的，先看[从 v0.1.0 升级](#从-v010-升级)。

## 交给 AI Agent 安装（推荐）

把下面这段话连同仓库链接发给你电脑上的 Claude Code / Codex：

> 按照 https://github.com/jacksonlin-infra/omarchy-doubao 的 AGENTS.md，在这台 Omarchy 上把豆包语音输入装好并验证。

Agent 会照着 [AGENTS.md](AGENTS.md) 做，中途只会问你两件事：火山引擎的凭据，以及（如果需要）让你在终端里输一次 sudo 密码。

## 手动安装

### 准备

- **系统**：Omarchy（Arch + Hyprland），在 Omarchy 4 上验证过。其他发行版见文末[非 Omarchy](#非-omarchy)。
- **网络**：能访问 `openspeech.bytedance.com`。
- **火山引擎账号**：开通豆包流式语音识别，拿到凭据（下一步）。

### 1. 拿到豆包语音识别的凭据

火山引擎有新旧两版控制台，凭据形式不同，**本项目两种都支持**：

| 控制台 | 你拿到的东西 | 安装参数 |
|---|---|---|
| 新版（新账号基本都是） | 一个 **API Key** | `--api-key` |
| 旧版 | **App ID** + **Access Token** | `--app-id` + `--access-token` |

新版控制台的步骤：

1. 登录火山引擎，进入「豆包语音」控制台。
2. 开通 **豆包流式语音识别模型 2.0**，计费方式选**按时长**（个人听写用量很小，单价以控制台为准）。
3. 在 API Key 管理页创建一个 API Key：<https://console.volcengine.com/speech/new/setting/apikeys>

> 控制台界面的叫法偶尔会调整，以官方文档为准：[大模型流式语音识别 API](https://www.volcengine.com/docs/6561/1354869)。

**资源 ID 必须和你开通的模型对上**，这是最常见的坑：

| 开通的模型 | `--resource-id` |
|---|---|
| 流式语音识别模型 2.0，按时长（默认） | `volc.seedasr.sauc.duration` |
| 流式语音识别模型 2.0，并发版 | `volc.seedasr.sauc.concurrent` |
| 流式语音识别模型 1.0，按时长 | `volc.bigasr.sauc.duration` |
| 流式语音识别模型 1.0，并发版 | `volc.bigasr.sauc.concurrent` |

### 2. 安装

```bash
git clone https://github.com/jacksonlin-infra/omarchy-doubao.git
cd omarchy-doubao
./install.sh --api-key '你的API Key'
```

旧版控制台：

```bash
./install.sh --app-id '你的App ID' --access-token '你的Access Token'
```

不带参数运行 `./install.sh` 会提示你输入（输入不回显）。开通的不是默认的 2.0 按时长版时，加上 `--resource-id`。

脚本做了这些事，重复运行是安全的：

1. 装系统包 `wtype wl-clipboard libnotify pipewire python-websockets python-gobject gtk4 gtk4-layer-shell`（Omarchy 上基本都已自带；缺的才装，需要时会调 sudo）。
2. 放听写服务 `~/.local/bin/doubao-dictate`。
3. 写凭据到 `~/.config/doubao-dictate/doubao.env`（权限 600；已有的凭据不会被清掉）。
4. 停用 Omarchy 自带的 voxtype 服务（不卸载，`./uninstall.sh` 会重新启用），免得两边抢麦克风。
5. 在 `~/.config/hypr/bindings.lua` 末尾写一段带标记的配置，把 F9 和 Super+Ctrl+X 从 voxtype 改绑到豆包听写，并重载 Hyprland。
6. 启用并启动用户服务 `doubao-dictate`，跑 `./check.sh` 自检。

以后更新：`git pull` 后重跑 `./install.sh`（不用再带凭据参数）。

### 3. 验证

```bash
./check.sh
```

每一项都应是 ✓。其中「豆包鉴权通过」一项会真的连一次豆包服务器，凭据和资源 ID 有问题会在这里直接报出来。

有一段录音（16kHz 单声道 WAV）的话，可以把识别链路测一遍：

```bash
./check.sh 录音.wav
```

最后在任意输入框里按住 F9 说一句话：屏幕底部出现悬浮条、边说边出字，松开后文字打到光标处，就全部完成了。

## 使用

| 快捷键 | 用法 |
|---|---|
| **按住 F9** | 按住说话，松开出字（最常用） |
| **Super + Ctrl + X** | 按一下开始，再按一下结束，适合长段落 |

- 说话时屏幕底部的悬浮条显示音量波形和实时识别结果，悬浮条不抢焦点，文字仍然打到你原来的窗口。
- 松开后悬浮条显示「识别中…」，豆包用非流式模型把整段再识别一遍（二遍识别），通常 1 秒内出最终结果。实时结果里偶尔的错字会在这一步纠正。
- 单次最长 300 秒（`doubao.env` 里的 `DICTATE_MAX_SECS`），到点自动结束。
- 某个窗口不接受模拟输入时，文字会落到剪贴板，`Ctrl+V` 粘贴即可。想一直只复制不打字，把 `DICTATE_OUTPUT` 改成 `clipboard`。
- 识别自带标点、把“二零二五年”写成“2025年”（`doubao.env` 里的 ITN / PUNC 开关）。“嗯”“这个”“那个”这类口水词目前会保留，自动去除计划在下一版用大模型润色来做。
- 改了 `doubao.env` 后执行 `systemctl --user restart doubao-dictate` 生效。

## 工作原理

```
按住 F9 ─▶ doubao-dictate start ─▶ pw-record 录音，每 200ms 一包 ─▶ 豆包 bigmodel_async（流式 + 二遍识别）
                                                                           │ 实时结果
                                      屏幕底部悬浮条（GTK4 layer-shell）◀──┘
松开 F9 ─▶ doubao-dictate stop  ─▶ 发最后一包 ─▶ 最终结果 ─▶ wtype 打到光标处
```

`doubao-dictate` 是一个用户级常驻服务（单个 Python 脚本，依赖 `python-websockets` 和 GTK4）。Hyprland 快捷键通过本地 socket 给它发 `start` / `stop` / `toggle`。按下时同时开始录音和连接豆包，连上之前录到的音会先缓存，不丢开头；说话时音频边录边发，所以松开时服务端只剩最后一点工作。

为什么不再用 Voxtype：Voxtype 的远程模式只会在松开后上传整段录音，没法边说边出字；它的流式模式只支持本地 Parakeet 和地址写死的 Soniox；它的悬浮层也只画波形、不显示文字。

## 安装了哪些文件

| 路径 | 作用 |
|---|---|
| `~/.local/bin/doubao-dictate` | 听写服务（录音、流式识别、悬浮条、上屏） |
| `~/.config/doubao-dictate/doubao.env` | 凭据和参数（600 权限，别提交到任何地方） |
| `~/.config/systemd/user/doubao-dictate.service` | 听写服务的用户服务，随桌面会话启动 |
| `~/.config/hypr/bindings.lua` 末尾的 `omarchy-doubao` 段 | F9 / Super+Ctrl+X 快捷键，卸载时整段删除 |
| `~/.local/state/omarchy-doubao/voxtype-was-enabled` | 记录安装前 voxtype 服务是开着的，卸载时据此重新启用 |

## 常见问题

`./check.sh` 会给出大部分问题的原因。排障时把 `doubao.env` 里的 `DOUBAO_DEBUG` 改成 `1`，然后：

```bash
systemctl --user restart doubao-dictate
journalctl --user -u doubao-dictate -f
```

调试日志会带上每一步的时间戳（松开、发出最后一包、收到最终结果），可以看出慢在本机还是服务端。

| 现象 / 报错 | 原因与处理 |
|---|---|
| `HTTP 401: Invalid X-Api-Key` | API Key 抄错或已删除；重新复制后 `./install.sh --api-key '...'` |
| `HTTP 401/403`（旧版控制台） | App ID 与 Access Token 不属于同一个应用，或抄漏了字符 |
| `HTTP 403: requested resource not granted` | 资源 ID 和开通的模型对不上；按上面的表改 `--resource-id`，或去控制台开通对应模型 |
| `HTTP 400: resourceId ... is not allowed` | 端点被改成了 `.../sauc/bigmodel`；改回 `bigmodel_async` |
| 按 F9 没反应 | 执行 `hyprctl reload` 或注销重登；再看 `systemctl --user status doubao-dictate`。服务没运行时按 F9 会弹通知提示 |
| 悬浮条出现了，但一直不出字 | 看 `journalctl --user -u doubao-dictate -n 30`；多半是凭据、资源 ID 或网络 |
| 悬浮条提示「没录到声音」 | 麦克风不可用；`wpctl status` 看默认输入设备，或在 `DICTATE_AUDIO_DEVICE` 里指定 |
| 说话时出字，但松开后没打到光标处 | 那个窗口不接受模拟输入，文字已在剪贴板里，`Ctrl+V` 粘贴 |
| 安装脚本退出码 3 | 装系统包需要 sudo 密码；在终端执行脚本打印的那条 `sudo pacman ...`，然后重跑 `./install.sh` |
| 识别慢 | 网络到 `openspeech.bytedance.com` 的延迟；挂了代理的话让这个域名直连 |

## 隐私

按住快捷键期间的录音会发送到火山引擎做识别，这是使用云端识别的前提；没按快捷键时不录音。服务只通过本机的 Unix socket（权限 600）接收命令，日志里只记录录音时长和识别出的字数；只有打开 `DOUBAO_DEBUG=1` 时才会把识别文字写进日志。

## 从 v0.1.0 升级

v0.1.0 是「Voxtype + 转接服务」方案，松开后才出字；v0.2.0 换成了自己的流式服务，两者的文件和服务都不一样，**先卸旧版、再装新版**：

```bash
cd omarchy-doubao
git pull --tags
git show v0.1.0:uninstall.sh | bash -s -- --purge   # 用 v0.1.0 自己的卸载脚本：移除转接服务、还原 voxtype 配置、删除旧凭据
./install.sh --api-key '你的API Key'                 # 旧版控制台用 --app-id / --access-token
```

凭据的存放位置变了（`~/.config/voxtype/` → `~/.config/doubao-dictate/`），所以装新版时要重新给一次。没卸旧版就运行新版 `install.sh` 时，脚本会停下并提示上面这条命令。

## 卸载

```bash
./uninstall.sh           # 移除听写服务和快捷键，重新启用 voxtype，保留凭据
./uninstall.sh --purge   # 连凭据文件一起删
```

卸载后 F9 回到 Omarchy 自带的 voxtype。Voxtype 本身属于 Omarchy，安装时只停用、不卸载；要彻底移除听写功能，用 Omarchy 菜单 → Remove → Dictation（或 `omarchy-voxtype-remove`）。

## 非 Omarchy

其他 Arch + Hyprland 系统也能用。`./install.sh` 照常运行，差别有两点：

- 悬浮条配色取自 Omarchy 当前主题；没有 Omarchy 时用内置的深色配色。
- 快捷键只会自动写进 Omarchy 的 `~/.config/hypr/bindings.lua`（Omarchy 4）或 `bindings.conf`（Omarchy 3，未实测）。都没有时脚本会提示，你自己在 Hyprland 配置里加：

```
bind = SUPER CTRL, X, exec, doubao-dictate toggle
bind = , F9, exec, doubao-dictate start
bindr = , F9, exec, doubao-dictate stop
```

## License

MIT
