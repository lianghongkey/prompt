# Prompt

## 如何安裝（How to install）

雙擊開啟下載到嘅 PKG 檔案，開始安裝。
按提示步驟進行。中途有可能系統設定App會彈出來，請求添加 Prompt 輸入法。
到最後一步，安裝程式會請求你登出電腦。要登出、再登入，Mac 輸入法先會正常生效。
請注意: 登出電腦會將所有程式結束運行。
安裝之後，如果見唔到有 Prompt 輸入法，請前往 系統設定App → 鍵盤 → 輸入方式，手動添加。

## 如何卸載（How to uninstall）

首先，去 系統設定App → 鍵盤 → 輸入方式，移除 Prompt。
跟住，刪除以下檔案／檔案夾：

/Library/Input\ Methods/Prompt.app
~/Library/Application\ Scripts/hk.eduhk.inputmethod.Prompt
~/Library/Containers/hk.eduhk.inputmethod.Prompt

## 如何構建（How to build）

前置要求（Build requirements）

macOS 15.0+
Xcode 16.0+
/Users/colin/develop/Prompt/rebuild.sh
/Users/colin/develop/Prompt/packaging/build_and_pack.sh
