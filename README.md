# Jarvis Installer — WECARE Hosting

Instala o assistente pessoal Jarvis no seu computador com um duplo-clique.
Tempo total: **~40 minutos** (a maior parte é download automático em segundo plano).

---

## 👔 Para Carlos

**📥 Baixar:** [instalar-jarvis-carlos.command](https://github.com/WECARE-HOSTING/jarvis-installer/raw/main/wrappers/instalar-jarvis-carlos.command)

1. Clique no link acima — o arquivo baixa direto pra pasta de Downloads
2. Abra a pasta de Downloads e **dê duplo-clique** no arquivo
3. Siga as instruções que aparecerem na tela — o computador faz o resto

> Se aparecer um aviso de segurança, veja a seção **"desenvolvedor não identificado"** abaixo.

---

## 💼 Para Gabi

**📥 Baixar:** [instalar-jarvis-gabriela.command](https://github.com/WECARE-HOSTING/jarvis-installer/raw/main/wrappers/instalar-jarvis-gabriela.command)

1. Clique no link acima — o arquivo baixa direto pra pasta de Downloads
2. Abra a pasta de Downloads e **dê duplo-clique** no arquivo
3. Siga as instruções que aparecerem na tela — o computador faz o resto

> Se aparecer um aviso de segurança, veja a seção **"desenvolvedor não identificado"** abaixo.

---

## 🗂️ Para Nicole

**📥 Baixar:** [instalar-jarvis-nicole.bat](https://github.com/WECARE-HOSTING/jarvis-installer/raw/main/wrappers/instalar-jarvis-nicole.bat)

1. Clique no link acima — o arquivo baixa direto pra pasta de Downloads
2. Abra a pasta de Downloads e **dê duplo-clique** no arquivo
3. Siga as instruções que aparecerem na tela — o computador faz o resto

> Se aparecer um aviso de segurança, veja a seção **"Windows protegeu seu PC"** abaixo.

---

## ⚠️ "Desenvolvedor não identificado" — Carlos e Gabi (Mac)

Isso é **normal** — o Mac exige uma etapa extra para arquivos baixados da internet que não passaram pela App Store. Não é vírus.

**O que fazer:**

1. 🚫 **Não clique em "Cancelar"** — feche a janela do aviso com o ✕
2. 📂 Abra o **Finder** e vá até a pasta onde o arquivo está salvo
3. 🖱️ Clique com o **botão direito** sobre o arquivo
4. 📋 No menu que abrir, clique em **"Abrir"**
5. ✅ Vai aparecer uma nova janela com o aviso — clique em **"Abrir"** novamente
6. ▶️ A instalação começa normalmente

---

## ⚠️ "Windows protegeu seu PC" — Nicole (Windows)

Isso é **normal** — o Windows exibe esse aviso para qualquer arquivo baixado fora da Microsoft Store. Não é vírus.

**O que fazer:**

1. 🔍 Na janela do aviso, clique em **"Mais informações"** (texto pequeno, canto superior esquerdo)
2. ▶️ Vai aparecer o botão **"Executar assim mesmo"** — clique nele
3. 🔐 Uma nova janela vai perguntar "Deseja permitir que este aplicativo faça alterações?" — clique em **"Sim"**
4. ✅ A instalação começa normalmente

---

## 🖥️ O que vai acontecer durante a instalação

A tela preta que abre é normal — é o instalador trabalhando. Você vai ver textos passando.

Em algum momento vai precisar da sua atenção:

| Momento | O que fazer |
|---|---|
| 🌐 **Browser abre pela 1ª vez** | Fazer login com seu e-mail @wecarehosting.com.br (Claude) |
| 🌐 **Browser abre pela 2ª vez** | Fazer login com Google @wecarehosting.com.br (VPN da empresa) |
| 📱 **QR code aparece no terminal** | Abrir WhatsApp no celular → Dispositivos Vinculados → Vincular Dispositivo → escanear |

Após o QR code, a instalação termina. Uma mensagem verde vai aparecer confirmando.

**Os 12GB de modelos continuam baixando em segundo plano** — você pode usar o computador normalmente. Leva ~30 minutos dependendo da sua internet.

---

## 🆘 Se algo der errado

Manda um print da tela preta para o Felipe: **felipe@wecarehosting.com.br**

Não tenta consertar sozinho — é mais rápido assim.

---

---

## 🔧 Manutenção (Felipe)

### Adicionar nova pessoa

1. Crie a pasta `profiles/<nome>/` com dois arquivos: `USER.md` e `CLAUDE.md`
   - Siga o padrão dos perfis existentes como referência
2. Crie o wrapper em `wrappers/`:
   - **Mac:** copie `instalar-jarvis-carlos.command`, troque `carlos` pelo novo perfil, `chmod +x`
   - **Windows:** copie `instalar-jarvis-nicole.bat`, troque `nicole` pelo novo perfil
3. Commit + push — o instalador já estará funcional via raw GitHub

### Atualizar perfil existente

Edite `profiles/<nome>/CLAUDE.md` ou `USER.md`, faça commit e push.

Pra aplicar a atualização na máquina do usuário, peça pra ele rodar este comando UMA VEZ:

```bash
# Mac — substituir <perfil> por carlos, gabriela ou nicole
curl -fsSL https://raw.githubusercontent.com/WECARE-HOSTING/jarvis-installer/main/profiles/<perfil>/CLAUDE.md \
  -o ~/.claude/CLAUDE.md
```

(Nada precisa ser reinstalado — apenas o arquivo de configuração é atualizado.)

### Debugar gateway — Mac

```bash
# Logs em tempo real
tail -f ~/Library/Logs/openclaw/gateway.log
tail -f ~/Library/Logs/openclaw/gateway.err

# Status do serviço
launchctl list | grep openclaw

# Reiniciar
launchctl unload ~/Library/LaunchAgents/com.openclaw.gateway.plist
launchctl load   ~/Library/LaunchAgents/com.openclaw.gateway.plist
```

### Debugar gateway — Windows

```powershell
# Logs
Get-Content "$env:USERPROFILE\.openclaw\logs\gateway.log" -Wait
Get-Content "$env:USERPROFILE\.openclaw\logs\gateway.err" -Wait

# Status do serviço
nssm status OpenClawGateway

# Reiniciar
nssm restart OpenClawGateway
```

### Debugar modelos Ollama

```bash
# Mac
tail -f ~/ollama-pull.log

# Windows (PowerShell)
Get-Content "$env:USERPROFILE\ollama-pull.log" -Wait
```
