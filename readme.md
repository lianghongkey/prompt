# Prompt 输入法

Prompt 是一款 macOS 普通话拼音输入法（IME），使用 Swift/SwiftUI 构建，以 SQLite 数据库存储词库。

## 如何安装

### PKG
双击打开下载的 PKG 文件，按提示步骤安装。安装过程中系统设置可能会弹出，请求添加 Prompt 输入法。

最后一步安装程序会请求注销电脑——注销并重新登录后，输入法才会正常生效。

安装后如果看不到 Prompt 输入法，请前往「系统设置 → 键盘 → 输入来源」手动添加。

### 编译安装

直接执行 rebuild.sh，重启电脑

## 如何卸载

首先，前往「系统设置 → 键盘 → 输入来源」移除 Prompt。

然后删除以下文件/文件夹：

```
sudo rm -rf /Library/Input\ Methods/Prompt.app
rm -rf ~/Library/Input\ Methods/Prompt.app
rm -rf ~/Library/Application\ Scripts/hk.eduhk.inputmethod.Prompt
rm -rf ~/Library/Containers/hk.eduhk.inputmethod.Prompt
```

## 如何构建

### 环境要求

- macOS 15.0+，Xcode 16.0+
- Python 3（仅用于词典扩展脚本）

### 项目结构

- **Prompt/** — 主 macOS 输入法应用（Swift/SwiftUI），注册为 IMKInputController
- **CoreIME/** — 核心引擎 Swift Package，由 Prompt 导入
- **Preparing/** — 独立 Swift Package，用于从 `pinyin.txt` 生成 `imedb.sqlite3`

### 重新生成词库（修改 pinyin.txt 后必须执行）

```bash
cd Preparing && swift run -c release && cd ..
```

### 完整重建（同时清除用户词库）

```bash
./rebuild.sh
```

## 查看调试日志

```bash
log stream --predicate 'subsystem == "hk.eduhk.inputmethod.Prompt"' --level debug --style compact
```

## 用户词库

应用已沙盒化，数据库位于容器内：

```bash
sqlite3 ~/Library/Containers/hk.eduhk.inputmethod.Prompt/Data/Library/userlexicon.sqlite3 \
  "SELECT * FROM userlexicontable ORDER BY frequency DESC LIMIT 20;"
```

## 常见问题

### 系统出现多个重复的中文键盘布局

#### 删除用户级别的旧副本（开发时安装的）
rm -rf ~/Library/Input\ Methods/Prompt.app

#### 退出当前运行的实例
osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'

#### 重启 TIS 服务，刷新输入法列表
killall -9 TextInputMenuAgent 2>/dev/null || true

#### 先退出输入法
osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'

#### 查看当前注册的输入法（找 Prompt 相关条目）
sudo /usr/libexec/PlistBuddy -c "Print :AppleEnabledInputSources" ~/Library/Preferences/com.apple.HIToolbox.plist

在 System Settings → Keyboard → Input Sources
里手动删除重复项是最安全的方式。如果删不掉（灰色或删了又回来），说明还有 /Library/Input
Methods/Prompt.app 的注册在系统级生效，需要：

#### 确认系统级安装是否存在
ls /Library/Input\ Methods/

#### 如果需要完全清除系统级安装
sudo rm -rf /Library/Input\ Methods/Prompt.app

#### 重启 TIS 服务
killall -9 cfprefsd
killall -9 TextInputMenuAgent

# 重启电脑

---

Bundle Identifier：`hk.eduhk.inputmethod.Prompt`
