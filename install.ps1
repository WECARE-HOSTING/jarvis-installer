#Requires -Version 5.1
param([string]$Profile = "")

$REPO_RAW     = "https://raw.githubusercontent.com/WECARE-HOSTING/jarvis-installer/main"
$OLLAMA_LOG   = "$env:USERPROFILE\ollama-pull.log"
$OPENCLAW_DIR = "$env:USERPROFILE\.openclaw"
$NSSM_SERVICE = "OpenClawGateway"
$GATEWAY_PORT = 18789

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ───────────────────────────────────────────────────────────────────

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Write-Log  { param($Msg) Write-Host "[jarvis] $Msg" -ForegroundColor Green }
function Write-Warn { param($Msg) Write-Host "[warn]   $Msg" -ForegroundColor Yellow }
function Write-Err  { param($Msg) Write-Host "[erro]   $Msg" -ForegroundColor Red; exit 1 }
function Write-Step { param($Msg) Write-Host "`n> $Msg" -ForegroundColor Cyan }

function Test-CmdExists {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-EnvPath {
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path","User")
}

function Invoke-WebRequestWithRetry {
    param([string]$Uri, [string]$OutFile)
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
            return
        } catch {
            Write-Warn "tentativa $i/3 falhou para $(Split-Path $OutFile -Leaf), aguardando 5s..."
            if ($i -lt 3) { Start-Sleep 5 }
        }
    }
    Write-Err "Falha ao baixar: $Uri"
}

# ── Auto-elevação ─────────────────────────────────────────────────────────────
# $MyInvocation.MyCommand.Path fica vazio quando invocado via iwr | iex,
# por isso re-baixa o script do GitHub antes de relançar elevado.

function Invoke-SelfElevate {
    if (Test-IsAdmin) { return }
    Write-Host "Solicitando permissoes de administrador..." -ForegroundColor Yellow
    $tempScript = "$env:TEMP\jarvis-install-$(Get-Random).ps1"
    Invoke-WebRequest -Uri "$REPO_RAW/install.ps1" -OutFile $tempScript -UseBasicParsing
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`" $Profile" -Verb RunAs
    exit 0
}

# ── 1. Perfil ─────────────────────────────────────────────────────────────────

function Check-Profile {
    if ($Profile -notin @('carlos','gabriela','nicole')) {
        Write-Err "Perfil invalido: '$Profile'. Use: carlos, gabriela ou nicole"
    }
    Write-Log "Perfil: $Profile"
}

# ── 2. Dependências base ──────────────────────────────────────────────────────

function Install-Winget {
    Write-Step "winget"
    if (Test-CmdExists winget) { Write-Log "winget ja disponivel"; return }
    Write-Warn "winget nao encontrado. Instale o App Installer pela Microsoft Store e reinicie."
    Read-Host "Pressione ENTER apos instalar o App Installer"
    if (-not (Test-CmdExists winget)) { Write-Err "winget ainda nao disponivel." }
}

function Install-Node {
    Write-Step "Node 24"
    Refresh-EnvPath
    if ((Test-CmdExists node) -and ((node --version 2>$null) -match '^v24')) {
        Write-Log "Node 24 ja instalado: $(node --version)"; return
    }
    Write-Log "Instalando Node 24 via winget..."
    winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e --silent
    Refresh-EnvPath
    Write-Log "Node: $(node --version)"
}

function Install-Bun {
    Write-Step "Bun"
    Refresh-EnvPath
    if (Test-CmdExists bun) { Write-Log "Bun ja instalado: $(bun --version)"; return }
    Write-Log "Instalando Bun..."
    irm bun.sh/install.ps1 | iex
    $env:Path += ";$env:USERPROFILE\.bun\bin"
    Write-Log "Bun instalado."
}

function Install-Uv {
    Write-Step "uv (Astral)"
    Refresh-EnvPath
    if (Test-CmdExists uv) { Write-Log "uv ja instalado: $(uv --version)"; return }
    Write-Log "Instalando uv..."
    irm https://astral.sh/uv/install.ps1 | iex
    $env:Path += ";$env:USERPROFILE\.local\bin"
    Write-Log "uv instalado."
}

function Persist-PathEnv {
    Write-Step "PATH persistente (HKCU)"
    $current = [Environment]::GetEnvironmentVariable("Path","User")

    $entries = @(
        "$env:USERPROFILE\.bun\bin",
        "$env:USERPROFILE\.local\bin",
        "$env:LOCALAPPDATA\wacli"
    )

    foreach ($entry in $entries) {
        if ($current -notlike "*$entry*") {
            $current += ";$entry"
            Write-Log "PATH += $entry"
        }
    }

    [Environment]::SetEnvironmentVariable("Path", $current, "User")
    Refresh-EnvPath
    Write-Log "PATH atualizado em HKCU\Environment."
}

# ── 3. Stack principal ────────────────────────────────────────────────────────

function Install-ClaudeCode {
    Write-Step "Claude Code"
    if (Test-CmdExists claude) { Write-Log "Claude Code ja instalado"; return }
    Write-Log "Instalando Claude Code..."
    npm install -g "@anthropic-ai/claude-code"
}

function Install-Ollama {
    Write-Step "Ollama"
    if (Test-CmdExists ollama) { Write-Log "Ollama ja instalado"; return }
    Write-Log "Instalando Ollama via winget..."
    winget install --id Ollama.Ollama --accept-package-agreements --accept-source-agreements -e --silent
    Refresh-EnvPath
}

function Install-Tailscale {
    Write-Step "Tailscale"
    if (Test-CmdExists tailscale) { Write-Log "Tailscale ja instalado"; return }
    Write-Log "Instalando Tailscale via winget..."
    winget install --id tailscale.tailscale --accept-package-agreements --accept-source-agreements -e --silent
    Refresh-EnvPath
}

function Install-Nssm {
    Write-Step "nssm"
    if (Test-CmdExists nssm) { Write-Log "nssm ja instalado"; return }
    Write-Log "Instalando nssm via winget..."
    winget install --id NSSM.NSSM --accept-package-agreements --accept-source-agreements -e --silent
    Refresh-EnvPath
}

# ── 4. wacli ──────────────────────────────────────────────────────────────────

function Install-Wacli {
    Write-Step "wacli"
    if (Test-CmdExists wacli) { Write-Log "wacli ja instalado"; return }
    Write-Log "Buscando release Windows via GitHub API..."

    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/openclaw/wacli/releases/latest" -UseBasicParsing
    } catch {
        Write-Warn "Falha ao consultar GitHub API para wacli."
        Write-Warn "wacli pulado — instale manualmente apos o setup."
        return
    }

    $archPattern = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64|aarch64' } else { 'x86_64|amd64' }
    $asset = $release.assets |
                 Where-Object { $_.name -match '[Ww]indows' -and $_.name -match $archPattern -and $_.name -match '\.zip$' } |
                 Select-Object -First 1

    if (-not $asset) {
        Write-Warn "Release Windows nao encontrado em openclaw/wacli/releases."
        Write-Warn "wacli pulado — instale manualmente apos o setup."
        return
    }

    $zipPath = "$env:TEMP\wacli.zip"
    $destDir = "$env:LOCALAPPDATA\wacli"
    Write-Log "Baixando $($asset.name)..."
    Invoke-WebRequestWithRetry -Uri $asset.browser_download_url -OutFile $zipPath
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
    Remove-Item $zipPath -ErrorAction SilentlyContinue
    Write-Log "wacli instalado em $destDir"
}

# ── 5. OpenClaw (npm) ─────────────────────────────────────────────────────────

function Install-OpenclawNpm {
    Write-Step "OpenClaw"
    if (Test-CmdExists openclaw) { Write-Log "openclaw ja instalado"; return }
    Write-Log "Instalando openclaw..."
    npm install -g openclaw
}

# TODO(felipe): confirmar se gogcli ainda e necessario (nao encontrado no setup atual)

# ── 6. Autenticações interativas ──────────────────────────────────────────────

function Auth-Claude {
    Write-Step "Autenticacao Claude Code"
    Write-Warn "O browser vai abrir para login OAuth."
    Write-Warn "Use sua conta @wecarehosting.com.br e volte aqui quando concluir."
    Read-Host "`nPressione ENTER para abrir o browser"
    claude login
    Write-Log "Claude Code autenticado."
}

function Install-ClaudeMem {
    Write-Step "Plugin claude-mem"

    $alreadyInstalled = $false
    try { $alreadyInstalled = (claude plugin list 2>$null) -match "claude-mem" } catch {}
    if ($alreadyInstalled) { Write-Log "claude-mem ja instalado"; return }

    $hasMarketplace = $false
    try { $hasMarketplace = (claude plugin marketplace list 2>$null) -match "thedotmack" } catch {}

    if (-not $hasMarketplace) {
        Write-Log "Adicionando marketplace thedotmack..."
        try {
            claude plugin marketplace add thedotmack/claude-mem
        } catch {
            Write-Warn "Falha ao adicionar marketplace thedotmack."
            Write-Warn "Apos este instalador, rode manualmente:"
            Write-Warn "  claude plugin marketplace add thedotmack/claude-mem"
            Write-Warn "  claude plugin install claude-mem@thedotmack"
            Read-Host "`nPressione ENTER para continuar"
            return
        }
    } else {
        Write-Log "Marketplace thedotmack ja configurado."
    }

    Write-Log "Instalando claude-mem@thedotmack..."
    try {
        claude plugin install claude-mem@thedotmack
        Write-Log "claude-mem instalado com sucesso."
    } catch {
        Write-Warn "Instalacao automatica falhou. Rode manualmente:"
        Write-Warn "  claude plugin install claude-mem@thedotmack"
        Read-Host "`nPressione ENTER para continuar"
    }
}

function Auth-Tailscale {
    Write-Step "Tailscale - VPN WECARE"
    $tsPath = "$env:ProgramFiles\Tailscale\tailscale-ipn.exe"
    if (Test-Path $tsPath) {
        Start-Process $tsPath -ErrorAction SilentlyContinue
    }
    Start-Sleep 2
    Write-Warn "Clique no icone do Tailscale na barra de tarefas -> 'Log in'."
    Write-Warn "Use sua conta Google @wecarehosting.com.br."
    Read-Host "`nPressione ENTER apos ver 'Connected' no menu"
    Write-Log "Tailscale configurado."
}

# ── 7. Modelos Ollama (background) ────────────────────────────────────────────

function Pull-ModelsBg {
    Write-Step "Download dos modelos Ollama"
    Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue
    Start-Sleep 3

    # Escreve script em arquivo temporario — Start-Process nao sobrevive com -Command inline longo
    $tmpScript = "$env:TEMP\ollama-pull.ps1"
    $logFile   = $OLLAMA_LOG
    @"
`$models = @('nomic-embed-text','mxbai-embed-large','qwen2.5:3b','qwen2.5:7b','qwen2.5-coder:7b')
foreach (`$m in `$models) {
    Add-Content -Path '$logFile' -Value "[`$(Get-Date -Format HH:mm:ss)] Baixando `$m..."
    ollama pull `$m 2>&1 | Out-Null
    Add-Content -Path '$logFile' -Value "[`$(Get-Date -Format HH:mm:ss)] OK: `$m"
}
Add-Content -Path '$logFile' -Value "[`$(Get-Date -Format HH:mm:ss)] Concluido."
"@ | Out-File -FilePath $tmpScript -Encoding UTF8

    Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tmpScript`"" -WindowStyle Hidden
    Write-Warn "Modelos (~12GB) sendo baixados em background (~30min)."
    Write-Warn "Acompanhe: Get-Content '$OLLAMA_LOG' -Wait"
}

# ── 8. MDs do perfil ──────────────────────────────────────────────────────────

function Download-ProfileMds {
    Write-Step "Baixando perfil Jarvis ($Profile)"
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude"    -Force | Out-Null
    New-Item -ItemType Directory -Path "$OPENCLAW_DIR\workspace"     -Force | Out-Null

    Invoke-WebRequestWithRetry -Uri "$REPO_RAW/profiles/$Profile/CLAUDE.md" -OutFile "$env:USERPROFILE\.claude\CLAUDE.md"
    Invoke-WebRequestWithRetry -Uri "$REPO_RAW/profiles/$Profile/USER.md"   -OutFile "$OPENCLAW_DIR\workspace\USER.md"
    Invoke-WebRequestWithRetry -Uri "$REPO_RAW/shared/SOUL.md"              -OutFile "$OPENCLAW_DIR\workspace\SOUL.md"
    Invoke-WebRequestWithRetry -Uri "$REPO_RAW/shared/IDENTITY.md"          -OutFile "$OPENCLAW_DIR\workspace\IDENTITY.md"

    Write-Log "MDs instalados:"
    Write-Log "  $env:USERPROFILE\.claude\CLAUDE.md"
    Write-Log "  $OPENCLAW_DIR\workspace\{USER,SOUL,IDENTITY}.md"
}

# ── 9. NSSM service ───────────────────────────────────────────────────────────

function Setup-Nssm {
    Write-Step "OpenClaw Gateway (servico Windows)"
    New-Item -ItemType Directory -Path "$OPENCLAW_DIR\logs" -Force | Out-Null

    $nodePath    = Split-Path (Get-Command node -ErrorAction Stop).Source
    $openclawPath = Split-Path (Get-Command openclaw -ErrorAction Stop).Source

    # Wrapper .cmd garante PATH correto no contexto do servico Windows (sem env de usuario)
    $wrapperPath = "$OPENCLAW_DIR\start-gateway.cmd"
    @"
@echo off
set PATH=$nodePath;$openclawPath;%PATH%
set OPENCLAW_PROFILE=$Profile
openclaw gateway --port $GATEWAY_PORT
"@ | Out-File -FilePath $wrapperPath -Encoding ASCII

    # Remove servico anterior se existir
    $svc = Get-Service -Name $NSSM_SERVICE -ErrorAction SilentlyContinue
    if ($svc) {
        nssm stop   $NSSM_SERVICE 2>$null
        nssm remove $NSSM_SERVICE confirm 2>$null
        Start-Sleep 2
    }

    nssm install $NSSM_SERVICE "cmd.exe" "/c `"$wrapperPath`""
    nssm set     $NSSM_SERVICE AppDirectory  $OPENCLAW_DIR
    nssm set     $NSSM_SERVICE AppStdout     "$OPENCLAW_DIR\logs\gateway.log"
    nssm set     $NSSM_SERVICE AppStderr     "$OPENCLAW_DIR\logs\gateway.err"
    nssm set     $NSSM_SERVICE Start         SERVICE_AUTO_START
    nssm start   $NSSM_SERVICE
    Write-Log "OpenClawGateway registrado e iniciado via nssm (porta $GATEWAY_PORT)"
}

# ── 10. WhatsApp ──────────────────────────────────────────────────────────────

function Pair-Whatsapp {
    Write-Step "Pareamento WhatsApp"
    if (-not (Test-CmdExists wacli)) {
        Write-Warn "wacli nao instalado. Pareamento pulado."
        Write-Warn "Instale manualmente e rode: wacli login"
        return
    }
    Write-Warn "O QR code vai aparecer abaixo."
    Write-Warn "No celular: WhatsApp > Dispositivos Vinculados > Vincular Dispositivo"
    Write-Host ""
    wacli login
}

# ── 11. Resumo ────────────────────────────────────────────────────────────────

function Show-Summary {
    Write-Host ""
    Write-Host "+------------------------------------------+" -ForegroundColor Green
    Write-Host "|   Jarvis instalado com sucesso!          |" -ForegroundColor Green
    Write-Host "+------------------------------------------+" -ForegroundColor Green
    Write-Host ""
    Write-Log "Perfil  : $Profile"
    Write-Log "Servico : nssm -> $NSSM_SERVICE (porta $GATEWAY_PORT)"
    Write-Log "Modelos : em download -> Get-Content '$OLLAMA_LOG' -Wait"
    Write-Host ""
    Write-Host "Proximos passos:"
    Write-Host "  1. Aguarde ~30min para os modelos Ollama terminarem"
    Write-Host "  2. Abra um novo Prompt de Comando e digite: claude"
    Write-Host "  3. O Jarvis ja esta configurado com seu perfil"
    Write-Host ""
    Write-Warn "Suporte: Felipe - felipe@wecarehosting.com.br"
}

# ── Main ──────────────────────────────────────────────────────────────────────

Invoke-SelfElevate

Write-Host ""
Write-Host "Jarvis Installer - WECARE Hosting" -ForegroundColor White
Write-Host "Perfil: $Profile"
Write-Host ""

Check-Profile
Install-Winget
Install-Node
Install-Bun
Install-Uv
Persist-PathEnv
Install-ClaudeCode
Install-Ollama
Install-Tailscale
Install-Nssm
Install-Wacli
Install-OpenclawNpm
Auth-Claude
Install-ClaudeMem
Auth-Tailscale
Pull-ModelsBg
Download-ProfileMds
Setup-Nssm
Pair-Whatsapp
Show-Summary
