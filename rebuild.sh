#!/bin/bash
# Rebuild database with latest pinyin.txt
echo "Building database..."
cd Preparing

# 删除用户词库数据库（沙盒容器内）
rm -f ~/Library/Containers/hk.eduhk.inputmethod.TypeDuck/Data/Library/userlexicon.sqlite3
# 清理旧的数据库文件（如果存在）
rm -f ~/Library/userlexicon.sqlite3 

xcodebuild -project TypeDuck.xcodeproj -scheme TypeDuck clean 

swift run -c release
cd ..


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





# 1. Xcode 构建缓存：Xcode 可能没有检测到图标文件变更，用了旧的缓存构建                                                                                
# 2. 系统图标缓存：macOS 会缓存所有应用图标，即使替换了.app里的图标也不会马上刷新                                                                      
# 3. 运行中的进程：如果 TypeDuck 还在运行，会继续使用旧的图标资源                                                                                      
# 解决步骤                                                                                                                                             
# # 1. 完全退出 TypeDuck                                                                                                                               
# osascript -e 'tell application id "hk.eduhk.inputmethod.TypeDuck" to quit'                                                                           
# # 2. 清除 Xcode 缓存                                                                                                                                 
# rm -rf ~/Library/Developer/Xcode/DerivedData/TypeDuck-*                                                                                              
# # 3. 清除系统图标缓存                                                                                                                                
# sudo rm -rf /Library/Caches/com.apple.iconservices.store                                                                                             
# sudo killall -9 com.apple.iconservices com.apple.dock                                                                                                
# # 4. 重新编译安装                                                                                                                                    
# xcodebuild -project TypeDuck.xcodeproj -scheme TypeDuck -destination 'platform=macOS' build                                                          
# cp -R ~/Library/Developer/Xcode/DerivedData/TypeDuck-*/Build/Products/Debug/TypeDuck.app ~/Library/Input\ Methods/                                   
# # 5. 重新启动 TypeDuck                                                                                                                               
# open ~/Library/Input\ Methods/TypeDuck.app     