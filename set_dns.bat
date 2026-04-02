@echo off
setlocal

:: 管理者権限チェック（管理者でなければ昇格）
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator privileges...
  >"%temp%\elevate.vbs" echo Set UAC = CreateObject("Shell.Application")
  >>"%temp%\elevate.vbs" echo UAC.ShellExecute "cmd.exe", "/c cd /d ""%cd%"" ^&^& ""%~f0""", "", "runas", 1
  cscript //nologo "%temp%\elevate.vbs"
  del "%temp%\elevate.vbs"
  exit /b
)

set "PRIMARY_DNS=192.168.1.1"
set "SECONDARY_DNS=10.20.30.40"
set "TARGET_ADAPTER="

for /f "tokens=*" %%I in ('netsh interface show interface ^| findstr /R /C:"Connected" /C:"接続"') do (
  for /f "tokens=1,2,3,*" %%A in ("%%I") do (
    set "TARGET_ADAPTER=%%D"
    goto :adapter_found
  )
)

:adapter_found
if not defined TARGET_ADAPTER (
  echo [ERROR] 接続中のネットワークアダプターを検出できませんでした。
  pause
  exit /b 1
)

echo 対象アダプター: %TARGET_ADAPTER%
echo DNS を設定しています...

netsh interface ip set dns name="%TARGET_ADAPTER%" static %PRIMARY_DNS% primary >nul 2>&1
if %errorlevel% neq 0 (
  echo [ERROR] プライマリ DNS の設定に失敗しました。
  pause
  exit /b 1
)

netsh interface ip add dns name="%TARGET_ADAPTER%" %SECONDARY_DNS% index=2 >nul 2>&1
if %errorlevel% neq 0 (
  echo [ERROR] セカンダリ DNS の設定に失敗しました。
  pause
  exit /b 1
)

echo [SUCCESS] DNS の設定が完了しました。
exit /b 0
