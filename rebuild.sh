#!/bin/bash
# Rebuild database with latest pinyin.txt
echo "Building database..."
cd Preparing
swift run -c release
cd ..

# 删除用户词库数据库（沙盒容器内）
rm -f ~/Library/Containers/hk.eduhk.inputmethod.TypeDuck/Data/Library/userlexicon.sqlite3
# 清理旧的数据库文件（如果存在）
rm -f ~/Library/userlexicon.sqlite3 

# Build TypeDuck
echo "Building TypeDuck..."
xcodebuild -project TypeDuck.xcodeproj -scheme TypeDuck -destination 'platform=macOS' build

# Install
echo "Installing TypeDuck..."
cp -R ~/Library/Developer/Xcode/DerivedData/TypeDuck-*/Build/Products/Debug/TypeDuck.app ~/Library/Input\ Methods/

# Restart input method
echo "Restarting TypeDuck..."
osascript -e 'tell application id "hk.eduhk.inputmethod.TypeDuck" to quit'
open ~/Library/Input\ Methods/TypeDuck.app

echo "Build and install complete!"

## 打开日志

# log stream --predicate 'subsystem == "hk.eduhk.inputmethod.TypeDuck"' --level debug --style compact

## 录音文件存储

# ~/Library/Containers/hk.eduhk.inputmethod.TypeDuck/Data/Documents/typeduck_recording.wav