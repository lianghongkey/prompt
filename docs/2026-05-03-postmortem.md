# 复盘：两个相关 bug 的根因与修复（2026-05-03）

本次会话定位并修复了两个看似不相关、但都源自"共享资源 + 隐式状态"假设破裂的 bug。

---

## Bug 1: `xiche` 输入匹配到"形成"（xing cheng）

### 现象

用户输入 `xiche`，候选列表里出现了"形成"（拼音 `xing cheng`），明显不该出现。

### 现场

- 用户的 `userlexicon.sqlite3` 里同时有 `洗车 (xi che)` 和 `形成 (xing cheng)`，频率 1000 / 3000。
- `形成` 排得很靠前，因为 `xing` 和 `xi` 的 shortcut intercode 都是 `xc` (4322)。

### 根因

`UserLexicon.runScheme` 的提前返回判定写错了。原代码：

```swift
let beforePingCount = out.count
if scheme.isAllFull {
    let matched = pingQuery(...)
    appendUnique(matched, into: &out, seen: &seenKeys)
    ...
    if out.count > beforePingCount { return }   // ← BUG
}
// fall through to shortcut + per-token PREFIX path
let shortcutMatched = shortcutSchemeQuery(...)
```

问题在于 `out` 是累积数组：

1. `directPingMatches` 已经把 `洗车` 放进 `out`（并写入 `seenKeys`）。
2. `runScheme([xi, che])` 记录 `beforePingCount = 1`。
3. 它自己的 `pingQuery` 又找到 `洗车`，但 `appendUnique` 因 `seenKeys` 命中去重了 → `out.count` 仍为 1。
4. `1 > 1 == false` → **没有提前 return**，落入 shortcut + 前缀路径。
5. shortcut=`xc` 命中 `形成` (xing cheng)，前缀匹配 `xi prefix-of xing` ✓ + `che prefix-of cheng` ✓ → 误匹配成功。

`Engine.runScheme` 有相同形态的写法，单 scheme 时不会触发（`out` 起始为空），但多 top scheme 命中相同行时同样会失误。

### 修复

把"是否提前返回"的依据从 `out.count` 变化改为 ping query 本身是否返回了行：

```swift
var pingProducedAny = false
let matched = pingQuery(...)
if !matched.isEmpty { pingProducedAny = true }
appendUnique(matched, into: &out, seen: &seenKeys)
// fuzzy 同理
if pingProducedAny { return }
```

文件：
- `CoreIME/Sources/CoreIME/Engine.swift:154-201`（runScheme 全 full 路径）
- `Prompt/UserLexicon.swift:235-269`（同上）

### 回归测试

`CoreIME/Tests/CoreIMETests/CoreIMETests.swift:testXicheAllFullDoesNotLeakLongerPrefix` —— 断言 `xiche` 的候选不含"形成"。

### 模糊音影响

无。模糊音的精确等价匹配（fuzzy ping query）也会让 `pingProducedAny = true`，仍然提前 return。唯一行为变化：当 ping/fuzzy ping 都只查到已被去重的候选时，原代码会误落入前缀路径，新代码不会 —— 这正是要修的 bug。

---

## Bug 2: Safari Cmd+T 新 tab 地址栏候选窗不显示

### 现象

- 中文模式下，Safari Cmd+T 开新 tab，光标自动落在地址栏，立即输入拼音 → 候选窗**完全看不见**（不是闪一下，是从头到尾没出现）。
- 用鼠标点别处再点回地址栏，再输入 → 候选窗正常出现。
- 输入功能本身正常，能选词、能 commit。

### 诊断过程

按猜测顺序排查：

1. **多显示器问题** —— 用户确认单屏，排除。
2. **光标缓存跨 composition 残留** —— 加了 `clearCurrentCursorBlock()` 在 `commitComposition` / `deactivateServer` 调用。但用户重新复现仍然看不见。
3. **加 WindowFrame 诊断日志** —— 抓到关键数据：
   ```
   setFrame: {{338, 615}, {800, 300}} level=20 visible=1 activeSpace=1
   ```
   窗口位置正确、`visible=1`、在 active space。**但 `level=20`**。
4. **z-order**：Safari URL 自动补全 popover 是 `NSPopUpMenuWindowLevel = 101`。我们 level 20 < 101 → 被遮住。

### 根因 A：窗口层级 heuristic 不可靠

```swift
// 旧代码
let preferredValue: Int = Int(clientLevel) + 1
guard preferredValue > minValue else { return idealValue }
guard preferredValue < maxValue else { return maxValue }
return preferredValue
```

Safari 地址栏 client 的 `windowLevel()` 返回 19（IMK 内部某层级），我们设成 20。但这个 heuristic 只比较了"是否高于 floating 层"，没考虑 popover 层（101）。

### 修复 A

直接用 `CGShieldingWindowLevel`（IME 标准做法 —— 比屏幕锁低 1，但比所有正常窗口和 popover 高）：

```swift
window.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
```

并在每次非 zero 的 `setFrame` 后强制 `orderFrontRegardless`：

```swift
window.setFrame(resolved, display: true)
if !resolved.isEmpty {
    window.orderFrontRegardless()
}
```

### 根因 B：多实例 `AppContext` race

修了 level 后用户测试：**还是看不见**，但发现"Cmd+T 失败、点击两次成功"。这是关键线索。

进一步检查：每次 `prepareWindow()` 都会重建 contentViewController：

```swift
window.contentViewController = NSHostingController(
    rootView: MotherBoard().environmentObject(appContext)
)
```

而 `appContext` 是 **per-instance lazy var**：

```swift
private lazy var appContext: AppContext = AppContext()
```

观察日志：1 秒内有 5 次 `Engine.prepare()`，对应 5 次 `activateServer` —— Safari 给每个 frame / popover / 地址栏自动补全各创建了独立的 `PromptInputController` 实例，每个有自己的 `AppContext`。

竞态场景：
1. 实例 A activate → `prepareWindow` → 共享窗口的 contentViewController 绑到 **A 的 appContext**。
2. 实例 B activate（Safari 又开了一个 IMK client）→ `prepareWindow` → 重新绑到 **B 的 appContext**。
3. 用户的键盘事件路由到 **A 实例** → A 的 candidates → A 的 appContext.update() →
   **窗口看到的是 B 的 appContext（空的），看不到 A 的内容**。
4. 鼠标点击 → 强制重新 activate 一次，最终落在某个稳定实例上 → 窗口的 contentViewController 和键盘事件落到同一个 appContext → 看得见。

### 修复 B

让 `AppContext` 跨实例共享，且 `contentViewController` 只绑一次：

```swift
// 跨实例共享单例
nonisolated(unsafe) private static let sharedAppContext: AppContext = AppContext()
private var appContext: AppContext { Self.sharedAppContext }

private func prepareWindow() {
    window.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
    if window.contentViewController == nil {
        window.contentViewController = NSHostingController(
            rootView: MotherBoard().environmentObject(appContext)
        )
    }
    window.orderFrontRegardless()
}
```

文件：`Prompt/PromptInputController.swift:17-30, 367-377`

### 同类隐患的扫描

按相同两个根因，下列宿主 / 场景理论上会触发同样问题，本次修复都覆盖了：

**根因 A（z-order 输给 popover）—— 已被 `CGShieldingWindowLevel` 覆盖**
- 其他浏览器：Chrome / Arc / Firefox / Edge —— URL 补全
- VSCode / JetBrains —— 代码补全 popover
- Office / Pages / Numbers —— 右键菜单、单元格补全
- Slack / Discord / Telegram —— @ 提及、emoji picker

**根因 B（多实例 race）—— 已被共享 AppContext 覆盖**
- 所有 WebKit 应用：Mail、App Store、Notes（webview 部分）
- Electron 应用（按 frame 拆 IMK client）
- 焦点频繁切换：Keynote/Numbers 切单元格、表单 Tab

### 残留隐患（低优先级）

- `currentClient` / `currentCursorBlock` 仍 per-instance。理论上多实例 race 时窗口位置可能用旧实例的光标算。但 `resolvedCursorBlock` 会重新查 `client?.cursorBlock`，实际很少踩到。
- `currentClient.didSet` 写共享 `appContext.quadrant`，多实例可能短暂闪烁 quadrant；下一次 `refreshQuadrant` 会修正。

---

## 经验教训

1. **共享单例 + per-instance 状态是危险组合**。Bug 1 是 `out` 数组在 caller 和 callee 之间共享但 callee 用增量判断；Bug 2 是窗口共享但 AppContext per-instance。统一为"全共享"或"全私有"，避免半混合。

2. **IMK 的 `PromptInputController` 不只一个实例**。Safari / Electron / 多 frame 应用会创建多个。任何"我以为只有一个"的代码都要审视。

3. **Heuristic 比 default 更危险**。`prepareWindow` 旧代码"如果有 client level 就用 client level + 1，否则用 ideal"，看起来更"智能"，实际上没考虑 popover。这种场景宁可用一个保守的高 default。

4. **诊断日志是定位 race 的主要工具**。Bug 2 单看代码很难想到 `level=20`，加了一行日志立刻看出问题。Bug 修完后及时清掉，否则会污染正常日志。

5. **"看似正常"是误导**。Bug 2 用户最初描述"输入功能正常但候选窗不见"，让人误以为是窗口位置或 z-order。其实 input 路径走的是另一个实例的 buffer，跟可见 UI 没在一个 appContext。

---

## 文件改动清单

```
CoreIME/Sources/CoreIME/Engine.swift                  # Bug 1: pingProducedAny
Prompt/UserLexicon.swift                              # Bug 1: pingProducedAny
CoreIME/Tests/CoreIMETests/CoreIMETests.swift         # Bug 1: 回归测试

Prompt/PromptInputController.swift                    # Bug 2: 共享 AppContext + level + orderFront
                                                      #        + clearCurrentCursorBlock
docs/2026-05-03-postmortem.md                         # 本文
CLAUDE.md                                             # 更新两处
```
