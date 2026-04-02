# AGENTS.md

このリポジトリで Codex が作業する際のルールです。

## 対象環境
- OS: Windows 11
- シェル: `cmd.exe`
- **PowerShell は使用禁止**

## 管理者権限が必要な操作の前提
管理者権限が必要な処理（例: システム設定変更、Program Files 配下への書き込み、サービス操作など）を行う前に、必ず以下を実施してください。

1. 現在の `cmd.exe` が管理者権限で実行中か確認する
2. 管理者権限でなければ UAC を表示して昇格を要求する

### cmd の実装例（PowerShell 不使用）
```bat
:: 管理者権限チェック
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator privileges...
  >"%temp%\elevate.vbs" echo Set UAC = CreateObject("Shell.Application")
  >>"%temp%\elevate.vbs" echo UAC.ShellExecute "cmd.exe", "/c cd /d ""%cd%"" ^&^& %~s0 %*", "", "runas", 1
  cscript //nologo "%temp%\elevate.vbs"
  del "%temp%\elevate.vbs"
  exit /b
)
```

## コミット運用
- **コミットはこまめに行うこと**
- 目安: **ひとかたまりの変更につき 1 コミット**

## 完了時
- 作業完了後は Pull Request を作成すること
