#!/bin/bash

# 删除用户词库数据库（沙盒容器内）
# rm -f ~/Library/Containers/hk.eduhk.inputmethod.Prompt/Data/Library/userlexicon.sqlite3

xcodebuild -project Prompt.xcodeproj -scheme Prompt clean 

# Rebuild database with latest pinyin.txt
echo "Building database..."
cd Preparing
swift run -c release
cd ..


# Build Prompt
echo "Building Prompt..."
xcodebuild -project Prompt.xcodeproj -scheme Prompt -destination 'platform=macOS' build

# Install
echo "Installing Prompt..."
rm -rf ~/Library/Input\ Methods/Prompt.app
cp -R ~/Library/Developer/Xcode/DerivedData/Prompt-*/Build/Products/Debug/Prompt.app ~/Library/Input\ Methods/

# Restart input method
echo "Restarting Prompt..."
osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'
open ~/Library/Input\ Methods/Prompt.app

echo "Build and install complete!"

## 打开日志

# log stream --predicate 'subsystem == "hk.eduhk.inputmethod.Prompt"' --level debug --style compact

## 词频数据保存的位置

# ~/Library/Containers/hk.eduhk.inputmethod.Prompt/Data/Library/userlexicon.sqlite3



# 1. Xcode 构建缓存：Xcode 可能没有检测到图标文件变更，用了旧的缓存构建                                                                                
# 2. 系统图标缓存：macOS 会缓存所有应用图标，即使替换了.app里的图标也不会马上刷新                                                                      
# 3. 运行中的进程：如果 Prompt 还在运行，会继续使用旧的图标资源                                                                                      
# 解决步骤                                                                                                                                             
# # 1. 完全退出 Prompt                                                                                                                               
# osascript -e 'tell application id "hk.eduhk.inputmethod.Prompt" to quit'                                                                           
# # 2. 清除 Xcode 缓存                                                                                                                                 
# rm -rf ~/Library/Developer/Xcode/DerivedData/Prompt-*                                                                                              
# # 3. 清除系统图标缓存                                                                                                                                
# sudo rm -rf /Library/Caches/com.apple.iconservices.store                                                                                             
# sudo killall -9 com.apple.iconservices com.apple.dock                                                                                                
# # 4. 重新编译安装                                                                                                                                    
# xcodebuild -project Prompt.xcodeproj -scheme Prompt -destination 'platform=macOS' build                                                          
# cp -R ~/Library/Developer/Xcode/DerivedData/Prompt-*/Build/Products/Debug/Prompt.app ~/Library/Input\ Methods/                                   
# # 5. 重新启动 Prompt                                                                                                                               
# open ~/Library/Input\ Methods/Prompt.app     