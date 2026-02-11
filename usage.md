
xcodebuild -project TypeDuck.xcodeproj -scheme TypeDuck -destination 'platform=macOS' build 
cp -R ~/Library/Developer/Xcode/DerivedData/TypeDuck-*/Build/Products/Debug/TypeDuck.app ~/Library/Input\ Methods/
open ~/Library/Input\ Methods/TypeDuck.app 

log stream --predicate 'subsystem == "hk.eduhk.inputmethod.TypeDuck"' --level debug


  # 切换到简体
  defaults write hk.eduhk.inputmethod.TypeDuck CharacterStandard -int 4

  # 切换到繁体
  defaults write hk.eduhk.inputmethod.TypeDuck CharacterStandard -int 1

  # 重启输入法生效
  osascript -e 'tell application id "hk.eduhk.inputmethod.TypeDuck" to quit'