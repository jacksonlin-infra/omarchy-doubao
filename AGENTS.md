# AGENTS.md — 给 AI Agent 的安装手册

你的任务：在用户这台 **Omarchy** 电脑上装好「豆包语音识别 + Voxtype」语音输入，并验证可用。
严格按下面的步骤做。所有命令都在本仓库根目录、以**普通用户**身份执行（不要 `sudo ./install.sh`）。

## 第 0 步：确认环境

```bash
grep -E '^ID=' /etc/os-release      # 期望 ID=omarchy
command -v pacman hyprctl
```

- `ID=omarchy`：继续。
- 不是 Omarchy 但有 pacman 和 Hyprland：读 README 的「非 Omarchy」一节，告诉用户需要先自行安装 voxtype，然后用 `--skip-packages` 安装，并把那三行 Hyprland 快捷键加到用户配置里。
- 没有 pacman：停下，告诉用户本项目不支持这个系统。

## 第 1 步：向用户要凭据

问用户用的是火山引擎**新版**还是**旧版**控制台，并索取对应凭据：

- 新版：一个 **API Key**
- 旧版：**App ID** 和 **Access Token**

同时问开通的是哪个模型。不知道就用默认值（模型 2.0、按时长 = `volc.seedasr.sauc.duration`），后面的鉴权检查会告诉你对不对。

用户还没有凭据时，把 README「1. 拿到豆包语音识别的凭据」那一节的步骤转述给他，等他拿到再继续。

规则：

- 不要编造、猜测或复用任何凭据。
- 不要把凭据回显到对话里、写进仓库文件、提交到 git，或放进命令历史以外的任何地方。
- 凭据只通过 `install.sh` 的参数传入，它会写进 `~/.config/voxtype/doubao.env`（权限 600）。

## 第 2 步：安装

新版控制台：

```bash
./install.sh --api-key '<API Key>'
```

旧版控制台：

```bash
./install.sh --app-id '<App ID>' --access-token '<Access Token>'
```

用户开通的不是 2.0 按时长版时，追加 `--resource-id <值>`。取值见 README 的资源 ID 表。

按退出码处理：

| 退出码 | 含义 | 你要做的 |
|---|---|---|
| 0 | 安装完成且 `check.sh` 全部通过 | 进入第 4 步 |
| 3 | 装系统包需要 sudo 密码，你的 shell 没法输入 | 把脚本打印的那条 `sudo pacman -S --needed --noconfirm ...` 原样交给用户，请他在自己的终端里执行；他确认完成后重跑同一条 `./install.sh` 命令 |
| 1 | 出错或自检未通过 | 读输出里的 ✗ 项，进入第 3 步 |

## 第 3 步：自检

```bash
./check.sh
```

必须每一项都是 ✓（`!` 是提示，不算失败）。常见 ✗ 的处理：

| ✗ 的内容 | 处理 |
|---|---|
| `HTTP 401 ... Invalid X-Api-Key` | API Key 不对。请用户重新复制，然后 `./install.sh --api-key '<新的>'` |
| `HTTP 401/403`，旧版凭据 | App ID 与 Access Token 不匹配。请用户核对后重装 |
| `requested resource not granted` | 资源 ID 与开通的模型不符。问用户开通的是哪个模型，用 `./install.sh --resource-id <值>` 重跑（不用重新给凭据） |
| `resourceId ... is not allowed` | `doubao.env` 的 `DOUBAO_ENDPOINT` 被改过。改回 `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream` |
| 服务没在运行 | `journalctl --user -u voxtype-doubao -n 50` 和 `journalctl --user -u voxtype -n 50`，按报错处理 |
| Hyprland 里没有 voxtype 快捷键 | 执行 `hyprctl reload`；你不在用户的桌面会话里时，请用户注销重登 |
| 不在 Hyprland 会话里，跳过快捷键检查 | 正常（例如通过 SSH 执行）。请用户在桌面上确认 F9 |

## 第 4 步：让用户实测

你没法替用户说话。请他：

1. 点进任意文本框（浏览器地址栏、终端都行）。
2. 按住 **F9**，屏幕底部出现波形条后说一句中文，松开。
3. 一两秒内带标点的文字出现在光标处，即为成功。

不成功时让他保持 `journalctl --user -u voxtype-doubao -f` 开着再试一次，把日志给你看。

## 不要做的事

- 不要下载 Whisper 等本地模型（`voxtype setup --download`、`voxtype setup model`）。本方案是远程识别，不需要本地模型。
- 不要在 Omarchy 上手动添加 F9 快捷键。Omarchy 在检测到 voxtype 后会自动绑定，重复绑定会冲突。
- 不要把 `driver_order` 里的 `wtype` 挪到后面，也不要换成 ydotool。ydotool 打不出中文。
- 不要把端点改成双向流式 `.../sauc/bigmodel`。
- 不要用 root 运行 `install.sh`。
- 不要改动 `doubao.env` 以外的地方来存放凭据。

## 卸载

```bash
./uninstall.sh           # 保留凭据
./uninstall.sh --purge   # 删除凭据
```
