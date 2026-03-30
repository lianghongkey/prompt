
xcodebuild -project Prompt.xcodeproj -scheme Prompt -destination 'platform=macOS' build 
cp -R ~/Library/Developer/Xcode/DerivedData/Prompt-*/Build/Products/Debug/Prompt.app ~/Library/Input\ Methods/
open ~/Library/Input\ Methods/Prompt.app 

log stream --predicate 'subsystem == "hk.eduhk.inputmethod.Prompt"' --level debug


  # 切换到简体
  defaults write hk.eduhk.inputmethod.Prompt CharacterStandard -int 4

  # 切换到繁体
  defaults write hk.eduhk.inputmethod.Prompt CharacterStandard -int 1

  # 重启输入法生效
  osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'


cd /Users/colin/develop/Prompt-Mac
rm -rf .build

# 运行 Python 脚本更新数据库
python3 /Users/colin/develop/Prompt-Mac/add_common_phrases.py
python3 /Users/colin/develop/Prompt-Mac/clean_and_expand_dict.py

# 重新构建
xcodebuild -scheme Prompt -configuration Debug


# 测试造词功能

## 测试步骤

1. **编译并安装应用**：
```bash
# 编译
xcodebuild -project Prompt.xcodeproj -scheme Prompt -destination 'platform=macOS' build

# 复制到输入法目录
cp -R ~/Library/Developer/Xcode/DerivedData/Prompt-*/Build/Products/Debug/Prompt.app ~/Library/Input\ Methods/

# 退出旧实例
osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'

# 启动新实例
open ~/Library/Input\ Methods/Prompt.app
```

2. **测试造词**：
   - 在任意文本编辑器中切换到 Prompt 输入法
   - 输入：`xulianlian`
   - 选择候选词中的"徐"（单字）
   - 选择候选词中的"两两"（双字词）
   - 观察是否输出"徐两两"

3. **查看日志**：
```bash
log stream --predicate 'subsystem == "hk.eduhk.inputmethod.Prompt"' --level debug --style compact
```

查找以下日志：
- `Enter word creation mode: candidate=徐`
- `Continue word creation: candidate=两两`
- `Syllable count: 2, bufferText before: lianlian`
- `Using segmentation: usedLength=8`
- `bufferText after: , wordCreationCharacters: ["徐", "两两"]`
- `Word creation completed: word=徐两两, pinyin=xu liang liang`
- `Saved to UserLexicon`

4. **验证保存**：
   - 再次输入：`xulianlian`
   - 检查候选列表中是否出现"徐两两"
   - 如果出现，说明保存成功

## 可能的问题

### 问题1：没有进入造词模式
- 检查日志是否有 `Enter word creation mode`
- 如果没有，说明选择"徐"时没有触发造词模式
- 可能原因：segmentation 失败或音节数判断错误

### 问题2：进入造词模式但没有继续
- 检查日志是否有 `Continue word creation`
- 如果没有，说明选择"两两"时没有继续造词
- 可能原因：`isInWordCreation` 判断失败

### 问题3：buffer 计算错误
- 检查日志中的 `bufferText before` 和 `bufferText after`
- 如果 `bufferText after` 不为空，说明没有正确移除已使用的拼音
- 可能原因：syllableCount 或 usedLength 计算错误

### 问题4：没有保存到 UserLexicon
- 检查日志是否有 `Word creation completed` 和 `Saved to UserLexicon`
- 如果没有，说明保存条件不满足
- 可能原因：`bufferText.isEmpty` 为 false 或 `wordCreationCharacters.count < 2`

### 问题5：保存了但查询不到
- 检查 UserLexicon 数据库：
```bash
sqlite3 ~/Library/userlexicon.sqlite3 "SELECT * FROM userlexicontable WHERE word = '徐两两';"
```
- 如果有记录，说明保存成功但查询逻辑有问题
- 检查 romanization 格式是否正确（应该是 "xu liang liang"）

## 调试技巧

1. **查看 segmentation**：
   - 在日志中查找 segmentation 相关信息
   - 确认 `lianlian` 是否正确分割为 ["lian", "lian"]

2. **查看 candidate.romanization**：
   - 确认"两两"的 romanization 是什么格式
   - 可能是 "liang liang" 或 "liang3 liang3"

3. **手动测试 UserLexicon**：
```swift
// 在代码中添加测试
let testCandidate = Candidate(text: "徐两两", romanization: "xu liang liang", input: "", mark: "")
UserLexicon.handle(testCandidate)
```

4. **检查数据库结构**：
```bash
sqlite3 ~/Library/userlexicon.sqlite3 ".schema userlexicontable"
```
