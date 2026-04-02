# Copilot Instructions

## Environment assumptions
- Windows 11
- Use `cmd.exe`
- Do not use PowerShell

## Privilege escalation policy
Before any operation that requires administrator rights, always:
1. Check whether current `cmd.exe` is already elevated.
2. If not elevated, prompt UAC and relaunch with admin rights.

### Example (cmd-only)
```bat
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

## Commit policy
- Commit frequently.
- Aim for one commit per logical chunk of changes.

## Completion policy
- Create a Pull Request after implementation is completed.
