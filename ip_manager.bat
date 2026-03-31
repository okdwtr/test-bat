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
:: 1. IP設定バックアップ
::   バッチファイルと同名の .cfg ファイルに現在の IP 設定を保存する
::   出力ファイル: %SCRIPT_DIR%%SCRIPT_NAME%.cfg
:: ============================================================
:BACKUP_IP
echo.
echo ---- IP 設定バックアップ ----
echo.

set "TEMP_CFG=%TEMP%\ipmgr_cfg_%RANDOM%.tmp"
set "TEMP_DNS=%TEMP%\ipmgr_dns_%RANDOM%.tmp"

netsh interface ipv4 show config name="!SELECTED_NIC!" > "%TEMP_CFG%" 2>nul
netsh interface ipv4 show dnsservers name="!SELECTED_NIC!" > "%TEMP_DNS%" 2>nul

if not exist "%TEMP_CFG%" (
    echo エラー: NIC "%SELECTED_NIC%" の設定を取得できませんでした。
    goto :BACKUP_CLEANUP
)

:: --- DHCP 状態を取得
::     netsh 出力の "DHCP" を含む行から DNS/WINS 以外の行を抽出し
::     行末トークン (Yes / No / はい / いいえ) を取得する
set "IP_DHCP="
set "_DHCP_LINE="
for /f "tokens=*" %%i in ('findstr /i "DHCP" "%TEMP_CFG%" ^| findstr /v /i "DNS\|WINS\|Server\|サーバー"') do (
    set "_DHCP_LINE=%%i"
)
for %%j in (!_DHCP_LINE!) do set "IP_DHCP=%%j"

:: --- IP アドレスを取得
::     "/" を含まない行から IPv4 パターンに合致する最初のトークンを抽出
set "IP_ADDR="
for /f "tokens=*" %%i in ('findstr /v "/" "%TEMP_CFG%"') do (
    if "!IP_ADDR!"=="" (
        for %%j in (%%i) do (
            if "!IP_ADDR!"=="" (
                echo %%j | findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
                if not errorlevel 1 set "IP_ADDR=%%j"
            )
        )
    )
)

:: --- サブネットマスクを取得
::     "/" を含む行 (サブネットプレフィックス行) の末尾 IPv4 トークンを抽出
::     例: "192.168.1.0/24 (mask 255.255.255.0)" → "255.255.255.0"
set "IP_MASK="
for /f "tokens=*" %%i in ('findstr "/" "%TEMP_CFG%"') do (
    set "_PFXLINE=%%i"
    set "_PFXLINE=!_PFXLINE:)=!"
    set "_LAST="
    for %%j in (!_PFXLINE!) do set "_LAST=%%j"
    echo !_LAST! | findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
    if not errorlevel 1 set "IP_MASK=!_LAST!"
)

:: --- デフォルトゲートウェイを取得
::     "Gateway" または "ゲートウェイ" を含む行のうち
::     "Metric" / "メトリック" を含まない行から IPv4 トークンを抽出
set "IP_GW="
for /f "tokens=*" %%i in ('findstr /i "Gateway\|ゲートウェイ" "%TEMP_CFG%" ^| findstr /v /i "Metric\|メトリック"') do (
    for %%j in (%%i) do (
        echo %%j | findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
        if not errorlevel 1 set "IP_GW=%%j"
    )
)

:: --- DNS サーバーを取得
::     dnsservers 出力のうち行頭がスペース+数字で始まる行を IPv4 として抽出
set "IP_DNS1="
set "IP_DNS2="
set "_DNS_COUNT=0"
for /f "tokens=*" %%i in ('findstr /r "^[ 	]*[0-9]" "%TEMP_DNS%"') do (
    echo %%i | findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
    if not errorlevel 1 (
        set /a _DNS_COUNT+=1
        if !_DNS_COUNT!==1 set "IP_DNS1=%%i"
        if !_DNS_COUNT!==2 set "IP_DNS2=%%i"
    )
)

:: --- バックアップファイルへ書き込み
(
    echo BACKUP_DATE=%DATE%
    echo BACKUP_TIME=%TIME%
    echo NIC=!SELECTED_NIC!
    echo IP_ADDR=!IP_ADDR!
    echo IP_MASK=!IP_MASK!
    echo IP_GW=!IP_GW!
    echo IP_DNS1=!IP_DNS1!
    echo IP_DNS2=!IP_DNS2!
    echo IP_DHCP=!IP_DHCP!
) > "!CONFIG_FILE!"

echo バックアップが完了しました。
echo 保存先: !CONFIG_FILE!
echo.
echo バックアップ内容:
echo ----------------------------------------
type "!CONFIG_FILE!"
echo ----------------------------------------

:BACKUP_CLEANUP
del "%TEMP_CFG%" >nul 2>&1
del "%TEMP_DNS%" >nul 2>&1
goto :EOF


:: ============================================================
:: 2. IP設定変更 (DHCP / 手動 切り替え)
::   現在の設定を確認し、DHCP と手動 (静的 IP) を相互に切り替える。
::   手動 → DHCP 切り替え時はバックアップを自動取得する。
:: ============================================================
:CHANGE_IP
echo.
echo ---- IP 設定変更 ----
echo.

:: --- 現在の DHCP 状態を取得
set "TEMP_CHK=%TEMP%\ipmgr_chk_%RANDOM%.tmp"
netsh interface ipv4 show config name="!SELECTED_NIC!" > "%TEMP_CHK%" 2>nul

set "_DHCP_LINE="
for /f "tokens=*" %%i in ('findstr /i "DHCP" "%TEMP_CHK%" ^| findstr /v /i "DNS\|WINS\|Server\|サーバー"') do (
    set "_DHCP_LINE=%%i"
)
del "%TEMP_CHK%" >nul 2>&1

set "_LAST_TOKEN="
for %%j in (!_DHCP_LINE!) do set "_LAST_TOKEN=%%j"

set "IS_DHCP=0"
if /i "!_LAST_TOKEN!"=="Yes"  set "IS_DHCP=1"
if   "!_LAST_TOKEN!"=="はい"  set "IS_DHCP=1"

if "!IS_DHCP!"=="1" (
    :: ----- DHCP → 手動 (静的 IP) -----
    echo 現在の設定: DHCP ^(自動^)
    echo.
    echo 手動 ^(静的 IP^) に切り替えます。
    echo.

    set "NEW_IP="
    set "NEW_MASK="
    set "NEW_GW="
    set "NEW_DNS1="
    set "NEW_DNS2="

    set /p "NEW_IP=  IP アドレス                            : "
    set /p "NEW_MASK=  サブネットマスク                      : "
    set /p "NEW_GW=  デフォルトゲートウェイ ^(空欄でスキップ^): "
    set /p "NEW_DNS1=  プライマリ DNS ^(空欄でスキップ^)      : "
    set /p "NEW_DNS2=  セカンダリ DNS ^(空欄でスキップ^)      : "

    if "!NEW_IP!"=="" (
        echo IP アドレスが入力されていません。キャンセルします。
        goto :EOF
    )
    if "!NEW_MASK!"=="" (
        echo サブネットマスクが入力されていません。キャンセルします。
        goto :EOF
    )

    echo.
    echo 設定を適用中...

    if "!NEW_GW!"=="" (
        netsh interface ipv4 set address name="!SELECTED_NIC!" static !NEW_IP! !NEW_MASK!
    ) else (
        netsh interface ipv4 set address name="!SELECTED_NIC!" static !NEW_IP! !NEW_MASK! !NEW_GW!
    )

    if not "!NEW_DNS1!"=="" (
        netsh interface ipv4 set dns name="!SELECTED_NIC!" static !NEW_DNS1!
        if not "!NEW_DNS2!"=="" (
            netsh interface ipv4 add dns name="!SELECTED_NIC!" !NEW_DNS2! index=2
        )
    ) else (
        netsh interface ipv4 set dns name="!SELECTED_NIC!" none
    )

    echo.
    echo 手動 ^(静的 IP^) 設定に変更しました。
) else (
    :: ----- 手動 → DHCP (切り替え前にバックアップを自動取得) -----
    echo 現在の設定: 手動 ^(静的 IP^)
    echo.
    echo DHCP に切り替える前に現在の設定をバックアップします...
    call :BACKUP_IP
    echo.
    echo DHCP に切り替えています...
    netsh interface ipv4 set address name="!SELECTED_NIC!" dhcp
    netsh interface ipv4 set dns name="!SELECTED_NIC!" dhcp
    echo.
    echo DHCP ^(自動^) 設定に変更しました。
)
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
