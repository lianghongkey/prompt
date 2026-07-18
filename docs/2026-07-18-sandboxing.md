# App Sandbox 迁移清单（2026-07-18）

把 Prompt 输入法从**非沙箱**改为 **App Sandbox** 运行的完整清单、影响面与验证/回滚步骤。
iCloud 词库同步**不在本次范围**（需付费开发者账号 + CloudKit，见文末）。

## 0. 前提与结论

- 沙箱本身用 **ad-hoc 签名即可**（`CODE_SIGN_IDENTITY="-"`，无 team）。`app-sandbox`、`device.audio-input`、`temporary-exception.*` 这些 entitlement 在 ad-hoc 下运行期都被系统认可（只有 App Store 审核会拒 temporary-exception）。
- **最大未知项**：输入法进程通过 `IMKServer`（`InputMethodConnectionName`）与系统 IMK 通信。系统自带输入法是沙箱的，第三方沙箱输入法也可行，但**必须真机安装后实测上屏**才能确认。本清单能把代码改对，但连接是否 OK 只能靠手测。

## 1. Entitlement 改动（`Prompt/Prompt.entitlements`）

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.device.audio-input</key>            <!-- 已有：麦克风 -->
<true/>
<!-- 一次性迁移旧词库用，迁移完成后的版本可删 -->
<key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
<array>
    <string>Library/userlexicon.sqlite3</string>
    <string>Library/userlexicon.sqlite3-wal</string>
    <string>Library/userlexicon.sqlite3-shm</string>
</array>
```

- 语音模型是**只读 bundle 资源**，沙箱下无需任何文件 entitlement。
- `home-relative-path` 里的 "home" 指**真实 home**（不是容器），所以能读到旧词库。

## 2. 用户词库路径与迁移

- `UserLexicon.swift` 用 `URL.libraryDirectory` / `.libraryDirectory,.userDomainMask` 定位 `userlexicon.sqlite3`。沙箱下这会**自动重定向到容器** `~/Library/Containers/hk.eduhk.inputmethod.Prompt/Data/Library/`——代码不用改路径，但**旧数据（真实 `~/Library/userlexicon.sqlite3`）会看不见**。
- **一次性迁移**：在打开数据库前，若容器内文件不存在、且真实 home 下旧文件存在，就 `copyItem` 过来（含 `-wal`/`-shm`）。读真实 home 用 `NSHomeDirectoryForUser(NSUserName())`（沙箱下仍返回真实 home），配合第 1 步的 temporary-exception 才有读权限。
- 迁移只在"容器内还没有库"时发生一次；之后容器库成为唯一真相源。

## 3. 跨进程/跨窗口探测：实测**不退化**（曾预测会退化，已用沙箱探针推翻）

用一个带 `com.apple.security.app-sandbox` 签名的 `.app` 探针实测（2026-07-18），以下 API 在沙箱下的返回值与非沙箱**完全一致**，真实 Prompt 进程也无任何 `sandboxd` 拒绝：

| 位置 / API | 功能 | 实测结果 |
|---|---|---|
| `PromptInputController.frontmostWindowKey`（`frontmostApplication` + `CGWindowListCopyWindowInfo`） | 排除 App 的跨窗口焦点重置 | **正常**。窗口列表含 OwnerPID + WindowNumber（key 用 `bundleID:CGWindowID`，不碰窗口标题） |
| `InputModeSettingsView` `runningApplications` / `urlForApplication` / `NSRunningApplication(withBundleIdentifier:)` | "从运行中的 App 选择"菜单 + App 名解析 | **正常**。88 个 app、85 个有 bundleId、全部有 localizedName |
| `AppDelegate` `didActivateApplicationNotification` | "被切到 ABC 时自动切回" | **正常**。`frontmostApplication` 能拿到他 App 的 bundleId + pid |

原因：这些是**只读的 Window Server / LaunchServices 查询，App Sandbox 不拦**。沙箱只拦窗口的**内容/标题**（`kCGWindowName` 需 Screen Recording (TCC)——实测 5 窗口仅 1 个拿到 Name），而上述功能都不使用窗口标题，故不受影响。

**唯一确有变化的是调试命令**（非功能退化，是路径变化）：

| CLAUDE.md 调试命令 | 沙箱后 |
|---|---|
| `sqlite3 ~/Library/userlexicon.sqlite3`、`defaults write hk.eduhk…` | 目标变成**容器内路径 / 容器 UserDefaults**，旧命令不再反映真实状态（已在 CLAUDE.md 更正） |

## 4. 不受影响

- 麦克风录音（entitlement 已具备）、语音模型加载（bundle 只读）、候选窗口（自己进程内的 NSPanel）、`imedb.sqlite3`（CoreIME 内置只读）、`TISRegisterInputSource`/安装流程（操作自身输入源）。

## 5. 验证步骤（必须真机手测）

1. `cd Preparing && swift run -c release`（如动过 DB）。
2. `xcodebuild -project Prompt.xcodeproj -scheme Prompt -destination 'platform=macOS' build`。
3. 装：`cp -R …/Build/Products/Debug/Prompt.app ~/Library/Input\ Methods/` → quit → open（见 CLAUDE.md）。
4. **实测清单**：
   - [ ] 能在多个 App 里正常上屏（IMK 连接 OK）——**头号验证项**
   - [ ] 首启后老词库词频还在（迁移成功）；`~/Library/Containers/hk.eduhk.inputmethod.Prompt/Data/Library/userlexicon.sqlite3` 存在
   - [ ] Shift+Space 语音录入正常（麦克风授权弹窗出现并可用）
   - [ ] 设置面板可打开、开关可用
   - [ ] （第 3 节实测已确认跨窗口/前台探测**不退化**；如需复核可再跑沙箱探针）
5. 用 `codesign -d --entitlements :- ~/Library/Input\ Methods/Prompt.app` 确认 `app-sandbox` 已生效；容器目录 `~/Library/Containers/hk.eduhk.inputmethod.Prompt/` 已生成。

## 6. 回滚

- 删除 `Prompt.entitlements` 里的 `app-sandbox`（和 temporary-exception）→ 重新构建安装即恢复非沙箱。
- 注意：一旦跑过沙箱版并迁移，"真相源"已在容器内；回滚到非沙箱会重新读真实 `~/Library/userlexicon.sqlite3`（旧库），**期间容器内的新增词频不会自动回流**。来回切换需手动同步库文件。

## 7. 以后：iCloud 同步（本次不做）

- 需**付费 Apple Developer Program** + App ID 开 iCloud capability + provisioning profile（当前 ad-hoc 做不了）。
- **不要**把活跃 `.sqlite3`（带 `-wal`/`-shm`）直接放进 iCloud Drive 容器 → 会损坏。
- 正确路线：**CloudKit 私有库**，本地 SQLite 仍为真相源，按 record 同步；输入法是后台 agent，推送不可靠，实际为"启动/激活拉取 + 防抖批量上传"。写入频繁（每次选词），需批处理。
