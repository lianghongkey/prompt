# Prompt 输入法

Prompt 是一款 macOS 普通话拼音输入法（IME），使用 Swift/SwiftUI 构建，以 SQLite 数据库存储词库。

## 主要特性

1. **完整词库内置** — 直接内置 100 万+ 词条，无须额外安装词库
2. **语音输入（本地）** — 使用 whisper.cpp 模型，按一个组合键即可语音转文本
   - 延迟低
   - 无隐私风险（完全本地）
   - 模型大小可任意选择（推荐 ChineseErrorCorrector3-4B）
3. **语音识别后处理（LLM 纠错）** — 通过本地 llama.cpp 服务器对语音识别结果做语法纠错
4. **Shift 单击切换中英文** — 单击左 Shift → 英文（ABC 直通）；单击右 Shift → 中文
5. **造词功能** — 通过选择单字组合自定义词组，自动入库并按使用频率排序
6. **交叉引用过滤** — 在已有候选词的情况下按住 Shift 输入辅助词的拼音，把候选缩小为某个共同音节位置上能与辅助词组合的字
7. **智能中文标点** — 在中文标点模式下，根据上下文自动在全角／半角之间切换（前一字符是中文 → 全角；前一字符是英文/数字 → 半角）
8. **删除选中的候选词** — `Shift+Space` 可从用户词库中删除当前第一个候选词
9. **中英文模式按 App 记忆 + 默认模式** — 同一个 App 上次切换的中／英文状态会被记住，下次激活恢复；新 App 用默认模式；Shift 单击随时手动切换

## 键盘快捷键

| 快捷键 | 状态 | 功能 |
|--------|------|------|
| 左/右方向键 | 候选词显示中 | 逐个移动高亮（到头/尾时自动翻页） |
| 上/下方向键 | 候选词显示中 | 翻页 |
| 数字键 1–9 | 候选词显示中 | 选择对应序号的候选词 |
| Space | 候选词显示中 | 选择当前高亮的候选词 |
| Shift+Space | 候选词显示中 | 从用户词库中删除第一个候选词（仅当其来自用户词库时生效） |
| Shift+Space | 中文模式 / 待机 | 启动语音输入（如果已配置 whisper 模型） |
| Shift+字母 | 候选词显示中 | 进入交叉引用过滤模式 |
| Esc | 候选词显示中 | 取消当前输入 / 退出过滤模式 |
| 单击左 Shift | 任何状态 | 切换到英文（ABC 直通）模式；如果已有未上屏拼音，则把拼音原样上屏后再切换 |
| 单击右 Shift | 任何状态 | 切换到中文模式 |

> Shift 单击规则：必须是**完整的「按下→松开」**且按住期间不超过 1 秒、不夹带其它键 / 修饰键，才会触发切换；按住 Shift 输入字母或与其它修饰键组合时不会切换。

## 功能详解

### 中英文模式选择

每次输入法被激活（切到一个新输入框／从别的输入法切回来）时，按以下优先级决定使用中文还是英文：

1. **该 App 上次切换的状态**（per-app 记忆）
   * 同一个 App 上次切到的中／英文状态会被记住，下次激活时恢复
   * 在「设置 → 输入法选择 → 不记忆输入法状态的 App」里加入的 App 会跳过这一层，直接落到下一层
2. **默认模式**（「设置 → 输入法选择 → 默认模式」，默认中文）

无论哪一层决定的结果，激活后都可以用 Shift 单击随时手动切换：

* 单击左 Shift → 英文（ABC 直通）；如果当前已有未上屏拼音，会把拼音原样上屏后再切换
* 单击右 Shift → 中文
* 也可以在「输入法选择」里打开「使用 Caps Lock 键切换到中文」，用 Caps Lock 替代右 Shift

### 语音输入

前置条件：在「设置 → 通用」中粘贴一个 `.mlmodelc` whisper 模型路径（同目录下需要有同名 `.bin` GGML 文件，模型名带 `-encoder` 时取去掉 `-encoder` 的基名）。

使用方法：
1. 在中文模式下，**不要**正在输入拼音（buffer 为空）
2. 按住 `Shift+Space`：开始录音，光标处显示 💬 标记，并播放 "Tink" 提示音
3. 松开任一键：停止录音，播放 "Pop" 提示音；模型推理完成后文本被自动上屏（繁体会自动转换为简体）

抗幻觉过滤：仅保留 `noSpeechProb < 0.4` 且段平均 token plog `> -1.0` 的片段，可有效过滤 whisper 在静默/噪声段的胡乱输出。

### LLM 后处理（语音纠错）

可选功能：把语音识别结果发送到本地 `llama-server` 做一遍纠错再上屏。

设置：在「设置 → 通用」中粘贴 `.gguf` 模型文件路径，点「应用」或「启动服务」。状态指示灯：
* 灰：未配置
* 黄：启动中
* 绿：运行中
* 橙：已停止（用户主动停止，不会自动重连）
* 红：启动失败

服务监听 `http://127.0.0.1:8081`；如该端口已存在响应 `/health` 的服务，会复用而不重复启动。语音识别完成后自动调用 `/v1/chat/completions` 端点（OpenAI 兼容协议）做纠错；超时（10 秒）或失败时回落为原始识别文本。

### 造词

输入两个或更多音节的拼音（如 `zhongguoren`），候选词列表里除了完整词，还会附带第一个音节的单字。

* 选择一个单字 → 进入造词模式（被选的字**不会立即上屏**，而是作为「预显示」一直跟着 marked text）
* 候选区刷新为剩余音节的候选；可继续选择单字或多字词
* 全部音节选完且至少有 2 段被组合时，组合后的整个词一次性上屏并保存进用户词库
* 造词过程中按 Backspace 会回滚最近的一次选择

支持 1+1、1+2、2+1、1+1+1 等任意组合。

### 交叉引用过滤（用辅助词缩小候选）

在已有候选词的情况下，按住 Shift 再输入辅助词的拼音，可以把候选缩小为「在共同音节位置上能与辅助词组合的字」。

举例：
1. 输入 `xiguan` → 候选：习惯、吸管、西关…
2. 按住 Shift 继续输入 `chengxi` → 系统找到共同音节 `xi`（位于 buffer 第 1 位、辅助词第 2 位）
3. 查询 `cheng xi` 对应的词：城西、承袭、晨曦、乘隙…
4. 提取这些词在 `xi` 位置上的字：{西、袭、曦、隙、溪、习、熙…}
5. 显示 `xi` 的单字候选，但仅保留上述集合中出现过的字
6. 选「曦」后进入造词模式，buffer 变为 `guan`

* Marked text 显示形如 `xi guan CHENXI`（辅助词大写）
* Backspace 一次清空整个辅助词、Esc 退出过滤、Space 或数字键正常选词
* 支持模糊音（zh↔z、in↔ing 等）匹配共同音节
* 在造词模式中也可继续过滤下一个字

### 智能标点（中文标点模式下）

在「中文标点」模式下，标点会根据**前一段输入**自动选择全/半角：

* 默认全角，输入 CJK 字符后保持全角
* 输入英文字母或数字后切换到半角
* 切换焦点／重新激活输入法时重置为全角

### 删除候选词（Shift+Space）

当候选词区显示且第一个候选词来自用户词库时，按 `Shift+Space` 可将其从 `~/Library/userlexicon.sqlite3` 中删除。如果第一个候选词不是用户词库条目，则无操作。

## 设置项

打开输入法菜单的「Prompt 设置」可配置：

* **设置**（通用）
  * 每页候选词数量（1–10）
  * 表情符号建议（开 / 关）
  * 输入记忆（开 / 关）；可一键清空
* **输入法选择**（中文 / 英文）
  * 默认模式（中文 / 英文）
  * 使用 Caps Lock 键切换到中文（开 / 关）
  * 不记忆输入法状态的 App 列表
* **语音识别模型路径**（`.mlmodelc`）
* **语音纠错服务**（`.gguf` 路径，启动 / 停止）
* **模糊音**（zh↔z、ch↔c、sh↔s、n↔l 等）

字符标准（简 / 繁）目前只能通过 defaults 修改：

```bash
# 切换到简体
defaults write hk.eduhk.inputmethod.Prompt CharacterStandard -int 4

# 切换到繁体
defaults write hk.eduhk.inputmethod.Prompt CharacterStandard -int 1

# 重启输入法生效
osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'
```

## 安装

### PKG

双击下载的 PKG 文件，按提示安装；安装最后一步会请求注销电脑，注销并重新登录后输入法生效。

如果安装后看不到 Prompt，请前往「系统设置 → 键盘 → 输入来源」手动添加。

### 源码编译安装

```bash
./rebuild.sh
```

> `rebuild.sh` 会同时清空用户词库；如果想保留用户词库，请手动按下文「构建」中的命令操作。

## 卸载

首先在「系统设置 → 键盘 → 输入来源」移除 Prompt，然后：

```bash
sudo rm -rf /Library/Input\ Methods/Prompt.app
rm -rf ~/Library/Input\ Methods/Prompt.app
rm -rf ~/Library/Application\ Scripts/hk.eduhk.inputmethod.Prompt
rm -rf ~/Library/userlexicon.sqlite3
```

## 构建

### 环境要求

* macOS 15.0+，Xcode 16.0+
* Python 3（仅用于词典扩展脚本）

### 项目结构

* **Prompt/** — 主 macOS 输入法应用（Swift/SwiftUI），注册为 `IMKInputController`
* **CoreIME/** — 核心引擎 Swift Package，由 Prompt 导入
* **Preparing/** — 独立 Swift Package，从 `pinyin.txt` 生成 `imedb.sqlite3`

### 重新生成词库（修改 pinyin.txt 后必须执行）

```bash
cd Preparing && swift run -c release && cd ..
```

### 仅编译并替换已安装的输入法（保留用户词库）

```bash
xcodebuild -project Prompt.xcodeproj -scheme Prompt -destination 'platform=macOS' build
cp -R ~/Library/Developer/Xcode/DerivedData/Prompt-*/Build/Products/Debug/Prompt.app ~/Library/Input\ Methods/
osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'
open ~/Library/Input\ Methods/Prompt.app
```

> 不要在 Xcode 中点 Run；输入法必须放在 `~/Library/Input Methods/` 才能被系统加载。

### 完整重建（同时清除用户词库）

```bash
./rebuild.sh
```

## 调试

### 实时日志

```bash
log stream --predicate 'subsystem == "hk.eduhk.inputmethod.Prompt"' --level debug --style compact
```

### 用户词库查询

```bash
sqlite3 ~/Library/userlexicon.sqlite3 \
  "SELECT * FROM userlexicontable ORDER BY frequency DESC LIMIT 20;"
```

## 常见问题

### 系统出现多个重复的 Prompt 输入法

最稳妥的做法是在「系统设置 → 键盘 → 输入来源」里手动删除重复项。如果删不掉（灰色或删了又回来），通常是同时存在用户级和系统级安装：

```bash
# 退出当前实例
osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'

# 删除用户级副本
rm -rf ~/Library/Input\ Methods/Prompt.app

# 如果系统级也存在，需 sudo 删除
ls /Library/Input\ Methods/
sudo rm -rf /Library/Input\ Methods/Prompt.app

# 刷新输入法服务
killall -9 cfprefsd
killall -9 TextInputMenuAgent

# 重启电脑
```

---

Bundle Identifier：`hk.eduhk.inputmethod.Prompt`
