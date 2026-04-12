# 交叉引用过滤（Cross-Reference Filter）

## 一、概念

输入目标词拼音后，按住 Shift 输入"辅助词"拼音，系统找出辅助词中共同音节位置的字，显示为单字候选列表，从而快速定位生僻字。

## 二、完整交互示例

```
目标：输入"曦光"

1. 输入 xiguang
   marked text:  xi guang
   候选词:       西光  希光  息光  熙光  ...

2. Shift+c
   marked text:  xi guang C
   filterText 无完整音节 → 候选不变

3. Shift+h,e,n,x,i → filterText = "chenxi"
   marked text:  xi guang CHENXI
   过滤:
     a. "chenxi" 分词 → [chen, xi]
     b. 查词库 → 晨曦, 陈曦, 辰溪 ...
     c. 共同音节 "xi" → 提取字: {曦, 溪, ...}
     d. 显示 xi 的单字候选，只保留交集中的字
   候选词:       西  系  细  戏  锡  喜  袭  希  溪  习  熙  曦 ...

4. 选择 "曦" → 进入造词模式，buffer 变为 guang
5. 选择 "光" → 输出 "曦光"，保存到用户词库
```

## 三、状态

```swift
// PromptInputController.swift
private var filterText: String = ""
private var isFiltering: Bool { filterText.isNotEmpty }
```

## 四、键盘行为（mandarin 模式，isBuffering 或 isFiltering 时）

| 按键 | 行为 |
|------|------|
| Shift+字母（有候选或已在过滤中） | 追加到 `filterText`，调用 `suggest()` 重新过滤 |
| Backspace（isFiltering 时） | 清空整个 `filterText`，`suggest()` 恢复原候选 |
| Escape（isFiltering 时） | 清空 `filterText`，`suggest()` 恢复原候选 |
| 空格/数字选择 | 选候选词，清空 `filterText` |
| 未输入拼音/无候选词时 Shift+字母 | 不进入过滤，正常输入大写字母 |
| 造词模式中 Shift+字母 | 可进入过滤，为后续字使用交叉引用 |

## 五、Marked Text 显示

filterText 显示为大写，空格分隔：

```
无过滤:    xi guang
过滤中:    xi guang CHENXI
过滤无效:  xi guang CH         ← 无完整音节，候选不变
```

## 六、过滤算法（`filterCandidates()` 方法）

```
输入:
  bufferText = "xiguan"    → bufferScheme = [xi, guan]
  filterText = "chengxi"   → filterScheme = [cheng, xi]

步骤:

1. 对 filterText 分词
   若无完整音节 → 返回空（候选不显示）

2. 找第一个共同音节（按 buffer 顺序，支持模糊音）
   bufferSyllables = [xi, guan]
   filterSyllables = [cheng, xi]
   对每个音节用 FuzzyPinyinExpander.expand() 展开变体，
   通过变体集合交集判断是否匹配（如 zhi↔zi、in↔ing 等）
   第一个共同音节 = xi（buffer 中的第一个匹配）
   若无交集 → 返回空

3. 查辅助词候选（Engine.suggest 内部已支持模糊音扩展）
   Engine.suggest("chengxi") → 城西, 承袭, 晨曦, 乘隙 ...
   UserLexicon.suggest("chengxi") → ...
   过滤：只保留音节数 == filterText 音节数的候选（不允许部分匹配）

4. 提取共同音节位置的字（支持模糊音匹配）
   将共同音节展开为变体集合（如 commonVariants = {xi}）
   遍历辅助词候选，若某位置拼音 ∈ commonVariants 则提取该位置的字
   城西 (cheng xi) → xi ∈ commonVariants → 西
   晨曦 (chen xi) → xi ∈ commonVariants → 曦
   辰溪 (chen xi) → xi ∈ commonVariants → 溪
   → allowedChars = {西, 袭, 隙, 习, 熙, 喜, 希, 溪, 曦, 玺, ...}

5. 查共同音节的所有单字候选
   Engine.suggest("xi") → 西, 系, 细, 戏, 洗, 吸, 席, ...

6. 过滤：只保留 allowedChars 中的字
   → 返回单字候选列表，input 设为 buffer 中对应音节的原始输入

用户选择一个字后，该字消耗 buffer 中对应音节的输入，
自动进入造词模式处理剩余音节。
```

## 七、代码实现

### `PromptInputController.swift`

- `filterText: String` — 过滤拼音状态
- `isFiltering: Bool` — 计算属性
- `process()` `.alphabet` 分支 — `isShifting && (isBuffering || isFiltering)` 时追加到 filterText
- `process()` `.backspace` 分支 — isFiltering 时清空 filterText
- `process()` `.escape` 分支 — isFiltering 时清空 filterText
- `suggest()` 末尾 — isFiltering 时调用 `filterCandidates()`
- `suggest()` marked text — 追加 filterSuffix（大写）
- `filterCandidates(_:)` — 核心过滤算法，返回过滤后的单字候选
- `clearBufferText()` / `deactivateServer()` / `aftercareSelection()` — 清空 filterText

### 无需修改的文件

- `CoreIME/Engine.swift` — 复用现有 `suggest()`
- `AppContext.swift` — marked text 在 controller 侧拼接

## 八、边界情况

| 情况 | 处理 |
|------|------|
| filterText 无完整音节（如 "ch"） | 候选显示为空 |
| 共同音节为空（如 filter="dama", buffer="xiguan"） | 候选为空 |
| filter 输入 3 个音节，词库只匹配前 2 个 | 不采用，要求音节数完全匹配 |
| 模糊音（如 zh/z）：buffer="zhi", filter="zi..." | 通过模糊音展开匹配为共同音节 |
| 过滤结果为空 | 候选为空 |
| 造词模式中按 Shift | 可进入过滤，为后续字使用交叉引用 |
| bufferText 变化（普通字母输入） | 重新 suggest + 重新过滤 |
| 非 buffering 时 Shift+Space | 仍触发语音识别，不受影响 |
