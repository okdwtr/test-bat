@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM 管理者権限チェック（AGENTS.md 指示に準拠）
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo 管理者権限で再実行します...
  >"%temp%\elevate.vbs" echo Set UAC = CreateObject("Shell.Application")
  >>"%temp%\elevate.vbs" echo UAC.ShellExecute "cmd.exe", "/c cd /d ""%cd%"" ^&^& %~s0 %*", "", "runas", 1
  cscript //nologo "%temp%\elevate.vbs"
  del "%temp%\elevate.vbs"
  exit /b
)

set "IFACE="
for /f "tokens=2 delims==" %%I in ('wmic nic where "NetConnectionStatus=2 and NetEnabled=true" get NetConnectionID /value ^| find "="') do (
  if not defined IFACE set "IFACE=%%I"
)

if not defined IFACE (
  echo [ERROR] 有効なネットワークインターフェースが見つかりませんでした。
  pause
  exit /b 1
)

set "IP="
set "MASK="
set "GW="
set /a IDX=0
for /f "tokens=*" %%L in ('netsh interface ipv4 show address name^="%IFACE%" ^| findstr /R "[0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*"') do (
  for /f "tokens=2 delims=:" %%A in ("%%L") do (
    set /a IDX+=1
    for /f "tokens=1" %%B in ("%%A") do (
      if !IDX! EQU 1 set "IP=%%B"
      if !IDX! EQU 2 set "MASK=%%B"
      if !IDX! EQU 3 set "GW=%%B"
    )
  )
)

if not defined IP (
  echo [ERROR] 現在のIPアドレスを取得できませんでした。
  pause
  exit /b 1
)
if not defined MASK (
  echo [ERROR] サブネットマスクを取得できませんでした。
  pause
  exit /b 1
)
if not defined GW (
  echo [ERROR] デフォルトゲートウェイを取得できませんでした。
  pause
  exit /b 1
)

for /f "tokens=1-4 delims=." %%a in ("%IP%") do (
  set "O1=%%a"
  set "O3=%%c"
  set "O4=%%d"
)

set "NEW_IP=%O1%.168.%O3%.%O4%"

echo 対象インターフェース: %IFACE%
echo 変更前IP: %IP%
echo 変更後IP: %NEW_IP%

netsh interface ipv4 set address name="%IFACE%" static %NEW_IP% %MASK% %GW% 1 >nul 2>&1
if errorlevel 1 (
  echo [ERROR] IPアドレスの設定に失敗しました。
  pause
  exit /b 1
)

echo [SUCCESS] IPアドレスの設定に成功しました。
timeout /t 2 >nul
exit /b 0
