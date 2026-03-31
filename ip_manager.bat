@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: IP設定管理ツール (Windows 11)
::
:: 機能:
::   1. IP設定のバックアップ
::      バッチファイルと同名の .cfg ファイルに保存
::   2. IP設定の変更 (DHCP / 手動 切り替え)
::      手動→DHCPへの切り替え前に自動バックアップ
::   3. IP設定の復元
::      バックアップ .cfg ファイルから設定を復元
::
:: 動作環境: Windows 11
:: 必須ツール: netsh (PowerShell 不使用)
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_NAME=%~n0"
set "CONFIG_FILE=%SCRIPT_DIR%%SCRIPT_NAME%.cfg"

:: ============================================================
:: メインメニュー
:: ============================================================
:MAIN_MENU
cls
echo ============================================================
echo  IP設定管理ツール
echo ============================================================
echo.
echo   1. IP設定のバックアップ
echo   2. IP設定の変更 ^(DHCP / 手動 切り替え^)
echo   3. IP設定の復元
echo   0. 終了
echo.
set "MENU_CHOICE="
set /p "MENU_CHOICE=選択してください (0-3): "

if "!MENU_CHOICE!"=="1" (
    call :SELECT_NIC
    if not "!SELECTED_NIC!"=="" call :BACKUP_IP
    echo.
    pause
    goto MAIN_MENU
)
if "!MENU_CHOICE!"=="2" (
    call :CHECK_ADMIN
    call :SELECT_NIC
    if not "!SELECTED_NIC!"=="" call :CHANGE_IP
    echo.
    pause
    goto MAIN_MENU
)
if "!MENU_CHOICE!"=="3" (
    call :CHECK_ADMIN
    call :RESTORE_IP
    echo.
    pause
    goto MAIN_MENU
)
if "!MENU_CHOICE!"=="0" (
    echo 終了します。
    goto :EOF
)
goto MAIN_MENU


:: ============================================================
:: 管理者権限チェック・UAC 昇格
:: ============================================================
:CHECK_ADMIN
net session >nul 2>&1
if %errorLevel% EQU 0 goto :EOF

echo.
echo  [警告] この操作には管理者権限が必要です。
echo  UAC プロンプトで承認すると、管理者として再起動します。
echo  承認しない場合はメインメニューに戻ります。
echo.
pause

set "VBS_FILE=%TEMP%\uac_elevate_%RANDOM%.vbs"
echo Set objShell = CreateObject^("Shell.Application"^) > "%VBS_FILE%"
echo objShell.ShellExecute "%~f0", "", "%~dp0", "runas", 1 >> "%VBS_FILE%"
cscript //nologo "%VBS_FILE%"
del "%VBS_FILE%" >nul 2>&1
exit


:: ============================================================
:: NIC 選択
:: 出力: SELECTED_NIC (選択された NIC 名)
:: ============================================================
:SELECT_NIC
set "SELECTED_NIC="
set "NIC_COUNT=0"
echo.
echo ---- 利用可能な NIC 一覧 ----
echo.

for /f "skip=2 tokens=1-3*" %%a in ('netsh interface show interface') do (
    if not "%%d"=="" (
        echo %%d | findstr /i "Loopback" >nul 2>&1
        if errorlevel 1 (
            set /a NIC_COUNT+=1
            for /f "tokens=*" %%e in ("%%d") do set "NIC_!NIC_COUNT!=%%e"
            for /f "tokens=*" %%e in ("%%d") do echo   !NIC_COUNT!. %%e
        )
    )
)

if !NIC_COUNT!==0 (
    echo 利用可能な NIC が見つかりませんでした。
    goto :EOF
)

if !NIC_COUNT!==1 (
    set "SELECTED_NIC=!NIC_1!"
    echo.
    echo 選択された NIC: !SELECTED_NIC!
    goto :EOF
)

echo.
:NIC_SELECT_LOOP
set "NIC_CHOICE="
set /p "NIC_CHOICE=対象 NIC を選択してください (1-!NIC_COUNT!, 0 でキャンセル): "

if "!NIC_CHOICE!"=="" goto NIC_SELECT_LOOP
if "!NIC_CHOICE!"=="0" (
    echo キャンセルしました。
    goto :EOF
)
echo !NIC_CHOICE! | findstr /r "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 goto NIC_SELECT_LOOP
if !NIC_CHOICE! lss 1 goto NIC_SELECT_LOOP
if !NIC_CHOICE! gtr !NIC_COUNT! goto NIC_SELECT_LOOP

for /l %%j in (1,1,!NIC_COUNT!) do (
    if !NIC_CHOICE!==%%j set "SELECTED_NIC=!NIC_%%j!"
)
echo.
echo 選択された NIC: !SELECTED_NIC!
goto :EOF


:: ============================================================
:: 1. IP設定バックアップ  ※ feature/ip-backup で実装
:: ============================================================
:BACKUP_IP
echo.
echo [未実装] IP 設定バックアップ機能は feature/ip-backup で実装されます。
goto :EOF


:: ============================================================
:: 2. IP設定変更  ※ feature/ip-change で実装
:: ============================================================
:CHANGE_IP
echo.
echo [未実装] IP 設定変更機能は feature/ip-change で実装されます。
goto :EOF


:: ============================================================
:: 3. IP設定復元
::   バックアップ .cfg ファイルから静的 IP 設定を復元する。
::   復元後は必ず手動 (静的 IP) 設定として適用される。
:: ============================================================
:RESTORE_IP
echo.
echo ---- IP 設定復元 ----
echo.

if not exist "!CONFIG_FILE!" (
    echo バックアップファイルが見つかりません。
    echo 場所: !CONFIG_FILE!
    echo.
    echo まず「1. IP 設定のバックアップ」を実行してください。
    goto :EOF
)

:: --- バックアップファイルを読み込む
::     "KEY=VALUE" 形式を KEY 変数に代入する
set "BACKUP_DATE="
set "BACKUP_TIME="
set "NIC="
set "IP_ADDR="
set "IP_MASK="
set "IP_GW="
set "IP_DNS1="
set "IP_DNS2="
set "IP_DHCP="

for /f "usebackq tokens=1,* delims==" %%a in ("!CONFIG_FILE!") do (
    set "%%a=%%b"
)

:: --- バックアップ内容を表示
echo バックアップ情報:
echo   バックアップ日時  : !BACKUP_DATE! !BACKUP_TIME!
echo   NIC               : !NIC!
echo   IP アドレス       : !IP_ADDR!
echo   サブネットマスク  : !IP_MASK!
echo   ゲートウェイ      : !IP_GW!
if not "!IP_DNS1!"=="" echo   DNS サーバー 1    : !IP_DNS1!
if not "!IP_DNS2!"=="" echo   DNS サーバー 2    : !IP_DNS2!
if not "!IP_DHCP!"=="" echo   バックアップ時DHCP: !IP_DHCP!
echo.

:: --- 必須項目の検証
if "!NIC!"=="" (
    echo エラー: バックアップファイルに NIC 情報がありません。
    goto :EOF
)
if "!IP_ADDR!"=="" (
    echo エラー: バックアップファイルに IP アドレス情報がありません。
    goto :EOF
)
if "!IP_MASK!"=="" (
    echo エラー: バックアップファイルにサブネットマスク情報がありません。
    goto :EOF
)

:: --- NIC の存在確認
set "_NIC_FOUND=0"
for /f "skip=2 tokens=1-3*" %%a in ('netsh interface show interface') do (
    for /f "tokens=*" %%e in ("%%d") do (
        if /i "%%e"=="!NIC!" set "_NIC_FOUND=1"
    )
)
if "!_NIC_FOUND!"=="0" (
    echo 警告: NIC "!NIC!" がこのシステムに存在しません。
    echo 別の NIC に復元する場合は、バックアップファイルを手動で編集してください。
    echo 場所: !CONFIG_FILE!
    goto :EOF
)

:: --- 実行確認
set "CONFIRM="
set /p "CONFIRM=この設定で IP を復元しますか? [Y/N]: "
if /i not "!CONFIRM!"=="Y" (
    echo 復元をキャンセルしました。
    goto :EOF
)

echo.
echo 設定を適用中...

:: --- 静的 IP アドレスを設定
if "!IP_GW!"=="" (
    netsh interface ipv4 set address name="!NIC!" static !IP_ADDR! !IP_MASK!
) else (
    netsh interface ipv4 set address name="!NIC!" static !IP_ADDR! !IP_MASK! !IP_GW!
)

:: --- DNS を設定
if not "!IP_DNS1!"=="" (
    netsh interface ipv4 set dns name="!NIC!" static !IP_DNS1!
    if not "!IP_DNS2!"=="" (
        netsh interface ipv4 add dns name="!NIC!" !IP_DNS2! index=2
    )
) else (
    netsh interface ipv4 set dns name="!NIC!" none
)

echo.
echo IP 設定を復元しました。^(手動 / 静的 IP として適用^)
goto :EOF
