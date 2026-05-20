# ============================================================
# ZqClaw Remote Agent (Windows)
# Usage:
#   连接:   irm https://zqclaw.itmsky.com/agent.ps1 | iex
#   卸载:   & ([scriptblock]::Create((irm https://zqclaw.itmsky.com/agent.ps1))) -Uninstall
# ============================================================

param(
    [switch]$Uninstall
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 | Out-Null } catch {}
Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

$RELAY_SERVER = "wss://47.107.130.152:8900"
$DOWNLOAD_URL = "https://zqclaw.itmsky.com/downloads/agent.exe"
$AGENT_DIR = "$env:TEMP\zqclaw"
$AGENT_PATH = "$AGENT_DIR\agent.exe"
$DEVICE_ID_PATH = "$env:LOCALAPPDATA\zqclaw\device-id"
$AUDIT_DIR = "$env:TEMP\zqclaw\sessions"
$TOKEN = "zqclaw-agent-pub"
$TIMEOUT_HOURS = 2

# ---- Uninstall path: kill running agents, delete files, exit ----
if ($Uninstall) {
    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Yellow
    Write-Host "    ZqClaw Remote Agent — 卸载" -ForegroundColor Yellow
    Write-Host "  ==========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  即将清理:" -ForegroundColor White
    Write-Host "    1. 结束所有正在运行的 agent.exe 进程" -ForegroundColor DarkGray
    Write-Host "    2. 删除 $AGENT_DIR (包含 agent.exe + 审计日志)" -ForegroundColor DarkGray
    Write-Host "    3. 删除 $DEVICE_ID_PATH (持久化 Device ID)" -ForegroundColor DarkGray
    Write-Host ""
    $ans = Read-Host "  确认卸载? (y/N)"
    if ($ans -ne "y" -and $ans -ne "Y") {
        Write-Host "  已取消。" -ForegroundColor Yellow
        return
    }

    # Kill any running agent processes (silent if none).
    Get-Process -Name "agent" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.Path -and $_.Path -like "*\zqclaw\agent.exe") {
                Write-Host "  [1/3] 结束进程 PID $($_.Id)" -ForegroundColor White
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Start-Sleep -Seconds 1
    Write-Host "  [1/3] 进程清理完成" -ForegroundColor Green

    # Remove agent + audit dirs.
    if (Test-Path $AGENT_DIR) {
        try {
            Remove-Item -Path $AGENT_DIR -Recurse -Force -ErrorAction Stop
            Write-Host "  [2/3] 已删除 $AGENT_DIR" -ForegroundColor Green
        } catch {
            Write-Host "  [2/3] 删除 $AGENT_DIR 失败 (可能有文件被占用): $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [2/3] $AGENT_DIR 不存在,跳过" -ForegroundColor DarkGray
    }

    # Remove persisted device ID directory.
    $deviceIdDir = Split-Path -Parent $DEVICE_ID_PATH
    if (Test-Path $deviceIdDir) {
        try {
            Remove-Item -Path $deviceIdDir -Recurse -Force -ErrorAction Stop
            Write-Host "  [3/3] 已删除 $deviceIdDir" -ForegroundColor Green
        } catch {
            Write-Host "  [3/3] 删除 $deviceIdDir 失败: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [3/3] $deviceIdDir 不存在,跳过" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  卸载完成 — 您的电脑上已没有 ZqClaw 远程协助的任何残留。" -ForegroundColor Green
    Write-Host "  下次需要时,重新运行 irm https://zqclaw.itmsky.com/agent.ps1 | iex 即可。" -ForegroundColor DarkGray
    Write-Host ""
    return
}

Clear-Host
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor Cyan
Write-Host "    ZqClaw Remote Agent" -ForegroundColor Cyan
Write-Host "  ==========================================" -ForegroundColor Cyan
Write-Host ""

# ---- Safety notice ----
Write-Host "  ! This script will:" -ForegroundColor Yellow
Write-Host "    1. Download a lightweight remote agent (~8MB)" -ForegroundColor DarkGray
Write-Host "    2. Connect to ZqClaw relay server" -ForegroundColor DarkGray
Write-Host "    3. Allow remote command execution for support" -ForegroundColor DarkGray
Write-Host "    4. Close this window to disconnect anytime" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  NOTE: Windows Defender / SmartScreen may show a warning" -ForegroundColor Yellow
Write-Host "  because the agent is not code-signed. This is normal." -ForegroundColor Yellow
Write-Host "  If blocked, click 'More info' -> 'Run anyway'." -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "  Continue? (y/N)"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host "  Cancelled." -ForegroundColor Red
    exit 0
}
Write-Host ""

# ---- Generate Device ID ----
$rand = Get-Random -Minimum 1000 -Maximum 9999
$DEVICE_ID = "pc-$rand"

# ---- Download Agent ----
Write-Host "  [1/2] Downloading agent..." -ForegroundColor White
try {
    if (!(Test-Path $AGENT_DIR)) { New-Item -ItemType Directory -Path $AGENT_DIR -Force | Out-Null }

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $AGENT_PATH -UseBasicParsing -TimeoutSec 120
    $ProgressPreference = 'Continue'

    if (!(Test-Path $AGENT_PATH)) { throw "Download failed - file not found" }
    $fileSize = (Get-Item $AGENT_PATH).Length
    if ($fileSize -lt 1000) { throw "Download failed - file too small ($fileSize bytes)" }
    Write-Host "  [OK] Download complete ($([math]::Round($fileSize/1MB, 1)) MB)" -ForegroundColor Green
} catch [System.Net.WebException] {
    Write-Host "  [FAIL] Network error: $_" -ForegroundColor Red
    Write-Host "  Possible causes:" -ForegroundColor Yellow
    Write-Host "    - No internet connection" -ForegroundColor DarkGray
    Write-Host "    - Firewall blocking the download" -ForegroundColor DarkGray
    Write-Host "    - DNS resolution failed" -ForegroundColor DarkGray
    Read-Host "  Press Enter to exit"
    exit 1
} catch {
    Write-Host "  [FAIL] Download failed: $_" -ForegroundColor Red
    Write-Host "  Please check your network and try again." -ForegroundColor Yellow
    Read-Host "  Press Enter to exit"
    exit 1
}

# Add Windows Defender exclusion hint
try {
    Add-MpPreference -ExclusionPath $AGENT_DIR -ErrorAction SilentlyContinue
} catch {
    # Non-admin users can't add exclusions - that's ok
}
Write-Host "  [TIP] If Defender blocks it: Settings > Virus protection > Allow" -ForegroundColor DarkGray

# ---- Run Agent ----
Write-Host "  [2/2] Connecting..." -ForegroundColor White
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor Green
Write-Host "    Connected! Send this ID to support:" -ForegroundColor Green
Write-Host "  ==========================================" -ForegroundColor Green
Write-Host ""
Write-Host ""
Write-Host "  Device ID:  $DEVICE_ID" -ForegroundColor Green
Write-Host ""
Write-Host "  Hostname:   $env:COMPUTERNAME" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  审计日志:   $env:TEMP\zqclaw\sessions\$(Get-Date -Format 'yyyy-MM-dd').log" -ForegroundColor DarkGray
Write-Host "             (运维每次执行命令都会记录,可随时打开查看)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  * Close this window to disconnect" -ForegroundColor DarkGray
Write-Host "  * Auto-disconnect after $TIMEOUT_HOURS hours" -ForegroundColor DarkGray
Write-Host ""

# Run agent with timeout
$agentProcess = Start-Process -FilePath $AGENT_PATH `
    -ArgumentList "-server", $RELAY_SERVER, "-token", $TOKEN, "-id", $DEVICE_ID `
    -NoNewWindow -PassThru

# Auto-timeout
$timeoutMs = $TIMEOUT_HOURS * 3600 * 1000
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while (!$agentProcess.HasExited) {
        if ($sw.ElapsedMilliseconds -ge $timeoutMs) {
            Write-Host ""
            Write-Host "  [!] Session timed out after $TIMEOUT_HOURS hours" -ForegroundColor Yellow
            $agentProcess.Kill()
            break
        }
        Start-Sleep -Seconds 1
    }
} catch {
    # User closed window or Ctrl+C
} finally {
    if (!$agentProcess.HasExited) {
        try { $agentProcess.Kill() } catch {}
    }
    # Cleanup
    try { Remove-Item -Path $AGENT_DIR -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ""
Write-Host "  Disconnected. You can close this window." -ForegroundColor Yellow
Read-Host "  Press Enter to exit"
