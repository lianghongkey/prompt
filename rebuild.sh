#!/bin/bash
# Rebuild database with latest pinyin.txt
echo "Building database..."
cd Preparing
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