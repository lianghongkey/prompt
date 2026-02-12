xcodebuild -project TypeDuck.xcodeproj -scheme TypeDuck -destination 'platform=macOS' build
cp -R ~/Library/Developer/Xcode/DerivedData/TypeDuck-*/Build/Products/Debug/TypeDuck.app ~/Library/Input\ Methods/
osascript -e 'tell application id "hk.eduhk.inputmethod.TypeDuck" to quit'
open ~/Library/Input\ Methods/TypeDuck.app