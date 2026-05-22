#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-}"
REPO_RAW="https://raw.githubusercontent.com/WECARE-HOSTING/jarvis-installer/main"
OLLAMA_LOG="$HOME/ollama-pull.log"
OPENCLAW_DIR="$HOME/.openclaw"
LAUNCHD_LABEL="com.openclaw.gateway"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"
GATEWAY_PORT=18789

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[jarvis]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $*"; }
err()  { echo -e "${RED}[erro]${NC}  $*" >&2; exit 1; }
step() { echo -e "\n${BLUE}${BOLD}▸ $*${NC}"; }

curl_retry() {
  local url="$1" dest="$2"
  for i in 1 2 3; do
    curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url" && return 0
    warn "tentativa $i/3 falhou para $(basename "$dest"), aguardando 5s..."
    sleep 5
  done
  err "Falha ao baixar: $url"
}

cmd_exists() { command -v "$1" &>/dev/null; }

# ── 1. Perfil ─────────────────────────────────────────────────────────────────

check_profile() {
  case "$PROFILE" in
    carlos|gabriela|nicole) log "Perfil: $PROFILE" ;;
    *) err "Perfil inválido: '${PROFILE:-<vazio>}'. Use: carlos, gabriela ou nicole" ;;
  esac
}

# ── 2. Dependências base ──────────────────────────────────────────────────────

install_homebrew() {
  step "Homebrew"
  if cmd_exists brew; then log "Homebrew já instalado"; return; fi
  log "Instalando Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon adiciona ao PATH da sessão atual
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

install_node() {
  step "Node 24"
  if cmd_exists node && node --version 2>/dev/null | grep -q "^v24"; then
    log "Node 24 já instalado: $(node --version)"; return
  fi
  log "Instalando node@24 via Homebrew..."
  brew install node@24
  brew link node@24 --force --overwrite
  local brew_prefix
  brew_prefix="$(brew --prefix)"
  export PATH="${brew_prefix}/opt/node@24/bin:$PATH"
  log "Node: $(node --version)"
}

install_bun() {
  step "Bun"
  if cmd_exists bun; then log "Bun já instalado: $(bun --version)"; return; fi
  log "Instalando Bun..."
  brew install oven-sh/bun/bun
}

install_uv() {
  step "uv (Astral)"
  if cmd_exists uv; then log "uv já instalado: $(uv --version)"; return; fi
  log "Instalando uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
}

persist_shellrc_path() {
  local zshrc="$HOME/.zshrc"
  touch "$zshrc"

  grep -q 'node@24/bin' "$zshrc" || \
    printf '\nexport PATH="$(brew --prefix)/opt/node@24/bin:$PATH"\n' >> "$zshrc"

  grep -q '\.local/bin' "$zshrc" || \
    printf 'export PATH="$HOME/.local/bin:$PATH"\n' >> "$zshrc"

  grep -q 'BUN_INSTALL' "$zshrc" || \
    printf 'export BUN_INSTALL="$HOME/.bun"\nexport PATH="$BUN_INSTALL/bin:$PATH"\n' >> "$zshrc"

  log "PATH exports adicionados em $zshrc"
}

# ── 3. Stack principal ────────────────────────────────────────────────────────

install_claude_code() {
  step "Claude Code"
  if cmd_exists claude; then log "Claude Code já instalado"; return; fi
  log "Instalando Claude Code..."
  npm install -g @anthropic-ai/claude-code
}

install_ollama() {
  step "Ollama"
  if cmd_exists ollama; then log "Ollama já instalado"; return; fi
  log "Instalando Ollama..."
  brew install --cask ollama
}

install_tailscale() {
  step "Tailscale"
  if cmd_exists tailscale; then log "Tailscale já instalado"; return; fi
  log "Instalando Tailscale..."
  brew install --cask tailscale
}

# ── 4. OpenClaw Gateway ───────────────────────────────────────────────────────

install_openclaw_npm() {
  step "OpenClaw"
  if ! cmd_exists openclaw; then
    log "Instalando openclaw..."
    npm install -g openclaw
  else
    log "openclaw já instalado"
  fi
}

setup_launchd() {
  local brew_prefix
  brew_prefix="$(brew --prefix)"

  mkdir -p "$HOME/Library/LaunchAgents"
  mkdir -p "$HOME/Library/Logs/openclaw"
  mkdir -p "$OPENCLAW_DIR"

  # Wrapper resolve PATH do node@24 no contexto do launchd (sem shell interativo)
  local wrapper="$OPENCLAW_DIR/start-gateway.sh"
  cat > "$wrapper" <<EOF
#!/bin/bash
export PATH="${brew_prefix}/opt/node@24/bin:${brew_prefix}/bin:/usr/local/bin:\$PATH"
export OPENCLAW_PROFILE="${PROFILE}"
exec openclaw gateway --port ${GATEWAY_PORT}
EOF
  chmod +x "$wrapper"

  cat > "$LAUNCHD_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${wrapper}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/openclaw/gateway.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/openclaw/gateway.err</string>
</dict>
</plist>
EOF

  launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
  launchctl load "$LAUNCHD_PLIST"
  log "openclaw-gateway registrado como serviço launchd (porta $GATEWAY_PORT)"
}

# ── 5. wacli ──────────────────────────────────────────────────────────────────

install_wacli() {
  step "wacli"
  if cmd_exists wacli; then log "wacli já instalado"; return; fi
  log "Instalando wacli..."
  brew tap openclaw/tap
  brew install wacli
}

# TODO(felipe): confirmar se gogcli ainda é necessário (não encontrado no setup atual)

# ── 6. Autenticações interativas ──────────────────────────────────────────────

auth_claude() {
  step "Autenticação Claude Code"
  warn "O browser vai abrir para login OAuth."
  warn "Use sua conta @wecarehosting.com.br e volte aqui quando concluir."
  read -rp $'\nPressione ENTER para abrir o browser... '
  claude login
  log "Claude Code autenticado."
}

install_claude_mem() {
  step "Plugin claude-mem"

  if claude plugin list 2>/dev/null | grep -qi "claude-mem"; then
    log "claude-mem já instalado"
    return 0
  fi

  if ! claude plugin marketplace list 2>/dev/null | grep -qi "thedotmack"; then
    log "Adicionando marketplace thedotmack..."
    if ! claude plugin marketplace add thedotmack/claude-mem; then
      warn "Falha ao adicionar marketplace thedotmack."
      warn "Após este instalador, rode manualmente:"
      warn "  claude plugin marketplace add thedotmack/claude-mem"
      warn "  claude plugin install claude-mem@thedotmack"
      read -rp $'\nPressione ENTER para continuar... '
      return 0
    fi
  else
    log "Marketplace thedotmack já configurado."
  fi

  log "Instalando claude-mem@thedotmack..."
  if claude plugin install claude-mem@thedotmack; then
    log "claude-mem instalado com sucesso."
  else
    warn "Instalação automática falhou. Rode manualmente:"
    warn "  claude plugin install claude-mem@thedotmack"
    read -rp $'\nPressione ENTER para continuar... '
  fi
}

auth_tailscale() {
  step "Tailscale — VPN WECARE"
  open -a Tailscale
  sleep 2
  warn "Clique no ícone do Tailscale na barra de menus (topo direito) → 'Log in'."
  warn "Use sua conta Google @wecarehosting.com.br."
  read -rp $'\nPressione ENTER após ver "Connected" no menu... '
  log "Tailscale configurado."
}

# ── 7. Modelos Ollama (background) ────────────────────────────────────────────

pull_models_bg() {
  step "Download dos modelos Ollama"
  open -a Ollama 2>/dev/null || true
  sleep 3

  {
    for model in nomic-embed-text mxbai-embed-large "qwen2.5:3b" "qwen2.5:7b" "qwen2.5-coder:7b"; do
      echo "[$(date '+%H:%M:%S')] Baixando $model..."
      ollama pull "$model" \
        && echo "[$(date '+%H:%M:%S')] OK: $model" \
        || echo "[$(date '+%H:%M:%S')] FALHOU: $model"
    done
    echo "[$(date '+%H:%M:%S')] Download completo."
  } >>"$OLLAMA_LOG" 2>&1 &

  warn "Modelos (~12GB) sendo baixados em background (~30min)."
  warn "Acompanhe: tail -f $OLLAMA_LOG"
}

# ── 8. MDs do perfil ──────────────────────────────────────────────────────────

download_profile_mds() {
  step "Baixando perfil Jarvis ($PROFILE)"
  mkdir -p "$HOME/.claude"
  mkdir -p "$OPENCLAW_DIR/workspace"

  curl_retry "${REPO_RAW}/profiles/${PROFILE}/CLAUDE.md"  "$HOME/.claude/CLAUDE.md"
  curl_retry "${REPO_RAW}/profiles/${PROFILE}/USER.md"    "$OPENCLAW_DIR/workspace/USER.md"
  curl_retry "${REPO_RAW}/shared/SOUL.md"                 "$OPENCLAW_DIR/workspace/SOUL.md"
  curl_retry "${REPO_RAW}/shared/IDENTITY.md"             "$OPENCLAW_DIR/workspace/IDENTITY.md"

  log "MDs instalados:"
  log "  ~/.claude/CLAUDE.md"
  log "  ~/.openclaw/workspace/{USER,SOUL,IDENTITY}.md"
}

# ── 9. WhatsApp ───────────────────────────────────────────────────────────────

pair_whatsapp() {
  step "Pareamento WhatsApp"
  warn "O QR code vai aparecer abaixo."
  warn "No celular: WhatsApp > Dispositivos Vinculados > Vincular Dispositivo"
  echo ""
  wacli login
}

# ── 10. Resumo ────────────────────────────────────────────────────────────────

print_summary() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║     Jarvis instalado com sucesso! 🤖     ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
  echo ""
  log "Perfil   : $PROFILE"
  log "Gateway  : launchd → $LAUNCHD_LABEL (porta $GATEWAY_PORT)"
  log "Modelos  : em download → tail -f $OLLAMA_LOG"
  echo ""
  echo "Próximos passos:"
  echo "  1. Aguarde ~30min para os modelos Ollama terminarem"
  echo "  2. Abra o Terminal e digite: claude"
  echo "  3. O Jarvis já está configurado com seu perfil"
  echo ""
  warn "Suporte: Felipe — felipe@wecarehosting.com.br"
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo -e "${BOLD}Jarvis Installer — WECARE Hosting${NC}"
  echo -e "Perfil: ${BOLD}${PROFILE:-?}${NC}"
  echo ""

  check_profile
  install_homebrew
  install_node
  install_bun
  install_uv
  persist_shellrc_path
  install_claude_code
  install_ollama
  install_tailscale
  install_wacli
  install_openclaw_npm
  auth_claude
  install_claude_mem
  auth_tailscale
  pull_models_bg
  download_profile_mds
  setup_launchd
  pair_whatsapp
  print_summary
}

main
