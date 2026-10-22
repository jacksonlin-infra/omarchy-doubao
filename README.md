# omarchy-doubao

在 [Omarchy](https://omarchy.org) 上用**豆包语音识别**做语音输入：按住 **F9** 说话，松开后带标点的中文直接打到光标处。浏览器、终端、编辑器、Claude Code / Codex 的输入框都能用。

豆包输入法没有 Linux 版，但它背后的识别引擎（火山引擎「豆包流式语音识别大模型」）开放了 API。本仓库把它接到 Omarchy 自带的听写工具 Voxtype 上，本机不跑任何模型。

## 交给 AI Agent 安装（推荐）

把下面这段话连同仓库链接发给你电脑上的 Claude Code / Codex：

> 按照 https://github.com/jacksonlin-infra/omarchy-doubao 的 AGENTS.md，在这台 Omarchy 上把豆包语音输入装好并验证。

Agent 会照着 [AGENTS.md](AGENTS.md) 做，中途只会问你两件事：火山引擎的凭据，以及（如果需要）让你在终端里输一次 sudo 密码。

## 手动安装

### 准备

- **系统**：Omarchy（Arch + Hyprland）。`voxtype-bin` 来自 Omarchy 软件源，F9 快捷键来自 Omarchy 默认配置。其他发行版见文末[非 Omarchy](#非-omarchy)。
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

1. 装系统包 `voxtype-bin wtype python-websockets ffmpeg`（已装的跳过，需要时会调 sudo）。
2. 放转接服务 `~/.local/bin/voxtype-doubao-shim`。
3. 写凭据到 `~/.config/voxtype/doubao.env`（权限 600；已有的凭据不会被清掉）。
4. 写 voxtype 配置 `~/.config/voxtype/config.toml`。原配置不同时会先备份成 `config.toml.bak.<时间>`。
5. 启用并启动两个用户服务 `voxtype-doubao`（转接）和 `voxtype`（录音/上屏），重载 Hyprland 让 F9 生效。
6. 跑 `./check.sh` 自检。

### 3. 验证

```bash
./check.sh
```

每一项都应是 ✓。其中「豆包鉴权通过」一项会真的连一次豆包服务器，凭据和资源 ID 有问题会在这里直接报出来。

有一段录音（16kHz 单声道 WAV）的话，可以把整条链路测一遍：

```bash
./check.sh 录音.wav
```

最后在任意输入框里按住 F9 说一句话，松开后文字出现，就全部完成了。

## 使用

| 快捷键 | 用法 |
|---|---|
| **按住 F9** | 按住说话，松开出字（最常用） |
| **Super + Ctrl + X** | 按一下开始，再按一下结束，适合长段落 |

- 录音时屏幕底部会出现音量波形条。
- 单次最长 60 秒（`config.toml` 里的 `max_duration_secs`）。
- 某个窗口不接受模拟输入时，文字会落到剪贴板，`Ctrl+V` 粘贴即可。
- 识别自带标点、把“二零二五年”写成“2025年”、去掉“嗯”“那个”等口水词（`doubao.env` 里的 ITN / PUNC / DDC 开关）。

## 工作原理

```
按住 F9 ─▶ voxtype 录音 ─▶ voxtype-doubao-shim (127.0.0.1:6688) ─▶ 火山引擎豆包识别
                ▲                                                      │
                └───────────── wtype 把文字打到光标处 ◀─── 文字 ────────┘
```

Voxtype 的远程模式只会说 OpenAI 的语音转写接口（上传音频、拿回 `{"text": ...}`），豆包识别用的是火山引擎自己的二进制 WebSocket 协议。`voxtype-doubao-shim` 是中间的翻译：一个约 400 行的 Python 脚本，只依赖 `python-websockets` 和 `ffmpeg`。

## 安装了哪些文件

| 路径 | 作用 |
|---|---|
| `~/.local/bin/voxtype-doubao-shim` | 转接服务 |
| `~/.config/voxtype/doubao.env` | 凭据和识别参数（600 权限，别提交到任何地方） |
| `~/.config/voxtype/config.toml` | voxtype 配置：remote 模式、中文、wtype 优先 |
| `~/.config/systemd/user/voxtype-doubao.service` | 转接服务的用户服务 |
| `~/.config/systemd/user/voxtype.service` | voxtype 自己的用户服务（由 `voxtype setup systemd` 生成，与 Omarchy 官方安装一致） |

## 常见问题

`./check.sh` 会给出大部分问题的原因。排障时把 `doubao.env` 里的 `DOUBAO_DEBUG` 改成 `1`，然后：

```bash
systemctl --user restart voxtype-doubao
journalctl --user -u voxtype-doubao -f
```

| 现象 / 报错 | 原因与处理 |
|---|---|
| `HTTP 401: Invalid X-Api-Key` | API Key 抄错或已删除；重新复制后 `./install.sh --api-key '...'` |
| `HTTP 401/403`（旧版控制台） | App ID 与 Access Token 不属于同一个应用，或抄漏了字符 |
| `HTTP 403: requested resource not granted` | 资源 ID 和开通的模型对不上；按上面的表改 `--resource-id`，或去控制台开通对应模型 |
| `HTTP 400: resourceId ... is not allowed` | 端点被改成了双向流式 `.../sauc/bigmodel`；改回 `bigmodel_nostream` |
| 按 F9 没反应 | Hyprland 只在加载配置时绑定 voxtype 快捷键：执行 `hyprctl reload` 或注销重登；再看 `systemctl --user status voxtype` |
| 波形条出现了，但没出字 | 看 `journalctl --user -u voxtype-doubao -n 30`；多半是凭据或资源 ID |
| 中文打不出来、只出英文或乱码 | `config.toml` 的 `driver_order` 第一位必须是 `wtype`；ydotool 打不了中文 |
| 安装脚本退出码 3 | 装系统包需要 sudo 密码；在终端执行脚本打印的那条 `sudo pacman ...`，然后重跑 `./install.sh` |
| 识别慢 | 网络到 `openspeech.bytedance.com` 的延迟；挂了代理的话让这个域名直连 |

## 隐私

录音会发送到火山引擎做识别，这是使用云端识别的前提。转接服务只在本机 `127.0.0.1` 监听，日志里只记录音频大小和识别出的字数；只有打开 `DOUBAO_DEBUG=1` 时才会把识别文字写进日志。

## 卸载

```bash
./uninstall.sh           # 移除转接服务，恢复安装前的 voxtype 配置，保留凭据
./uninstall.sh --purge   # 连凭据文件一起删
```

Voxtype 本身属于 Omarchy，不会被卸载；要彻底移除听写功能，用 Omarchy 菜单 → Remove → Dictation（或 `omarchy-voxtype-remove`）。

## 非 Omarchy

其他 Arch + Hyprland 系统也能用，差别只有两点：

1. 先按 <https://voxtype.io> 装好 voxtype，再运行 `./install.sh --skip-packages`（`wtype python-websockets ffmpeg` 自己用 pacman 装）。
2. 自己在 Hyprland 配置里加快捷键：

   ```
   bind = SUPER CTRL, X, exec, voxtype record toggle
   bind = , F9, exec, voxtype record start
   bindr = , F9, exec, voxtype record stop
   ```

## License

MIT
