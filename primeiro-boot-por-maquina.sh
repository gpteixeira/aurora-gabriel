#!/usr/bin/env bash
#
# primeiro-boot-por-maquina.sh
#
# Roda UMA VEZ em cada máquina, depois do "bootc switch" pra sua imagem
# customizada. Cobre só o que NÃO faz sentido morar no Containerfile:
#   - coisas de $HOME (Rust, Flutter) — não fazem parte da imagem
#   - coisas sensíveis (Warsaw) — de propósito fora da imagem versionada
#   - coisas específicas de CADA máquina (DeepCool só no desktop, MTU/DNS
#     dependem da rede local de cada uma)
#
# Uso:
#   bash primeiro-boot-por-maquina.sh

set -euo pipefail

c_reset="\e[0m"; c_green="\e[32m"; c_yellow="\e[33m"; c_blue="\e[34m"; c_bold="\e[1m"
info()  { echo -e "${c_blue}${c_bold}[*]${c_reset} $*"; }
ok()    { echo -e "${c_green}${c_bold}[OK]${c_reset} $*"; }
warn()  { echo -e "${c_yellow}${c_bold}[!]${c_reset} $*"; }

ask() {
    local prompt="$1" default="${2:-S}" ans
    read -rp "$prompt [$([ "$default" = S ] && echo "S/n" || echo "s/N")]: " ans
    ans=${ans:-$default}
    [[ "$ans" =~ ^[Ss]$ ]]
}

# ---------------------------------------------------------------------------
# Rust (rustup instala em ~/.cargo — precisa ser por usuário, não por imagem)
# ---------------------------------------------------------------------------
if ask "Instalar Rust (rustup) neste usuário?"; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ok "Rust instalado."
fi

# ---------------------------------------------------------------------------
# Konsole (Dark Pastels + Hack Nerd Font) e fastfetch — os arquivos-modelo já
# vieram na imagem (em /usr/share/gabriel-dotfiles), mas só são copiados pro
# SEU usuário aqui, porque $HOME fica fora da imagem e sua conta já existia
# antes do "bootc switch" (então /etc/skel não a alcançou).
# ---------------------------------------------------------------------------
if ask "Aplicar o tema do Konsole (Dark Pastels + Hack Nerd Font 11pt, 5% de transparência) e o layout do fastfetch neste usuário?"; then
    mkdir -p "$HOME/.local/share/konsole" "$HOME/.config/fastfetch"

    cp -n /usr/share/gabriel-dotfiles/konsole/DarkPastels.colorscheme "$HOME/.local/share/konsole/" 2>/dev/null || true
    cp -n /usr/share/gabriel-dotfiles/konsole/Gabriel.profile "$HOME/.local/share/konsole/" 2>/dev/null || true

    if [ -f "$HOME/.config/konsolerc" ] && ! grep -q "DefaultProfile=Gabriel.profile" "$HOME/.config/konsolerc"; then
        cp "$HOME/.config/konsolerc" "$HOME/.config/konsolerc.bak"
        warn "Backup do konsolerc anterior salvo em ~/.config/konsolerc.bak"
    fi
    mkdir -p "$HOME/.config"
    printf '[Desktop Entry]\nDefaultProfile=Gabriel.profile\n' > "$HOME/.config/konsolerc"

    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
        cp "$HOME/.config/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc.bak"
        warn "Backup do fastfetch config anterior salvo em ~/.config/fastfetch/config.jsonc.bak"
    fi
    cp /usr/share/gabriel-dotfiles/fastfetch/config.jsonc "$HOME/.config/fastfetch/config.jsonc"

    ok "Tema do Konsole e layout do fastfetch aplicados. Abra um Konsole novo para ver o resultado."
fi


# ---------------------------------------------------------------------------
# Flutter SDK (clone em ~/development — idem, por usuário)
# ---------------------------------------------------------------------------
if ask "Instalar Flutter SDK neste usuário?"; then
    FLUTTER_DIR="$HOME/development/flutter"
    if [ -d "$FLUTTER_DIR" ]; then
        info "Já existe em $FLUTTER_DIR — atualizando."
        (cd "$FLUTTER_DIR" && "$FLUTTER_DIR/bin/flutter" upgrade) || warn "Falha ao atualizar."
    else
        mkdir -p "$HOME/development"
        git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
    fi
    grep -q 'development/flutter/bin' "$HOME/.bashrc" || \
        echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> "$HOME/.bashrc"
    export PATH="$PATH:$FLUTTER_DIR/bin"
    "$FLUTTER_DIR/bin/flutter" precache --linux || warn "Precache falhou — rode manualmente depois."
    "$FLUTTER_DIR/bin/flutter" config --enable-linux-desktop
    ok "Flutter instalado em $FLUTTER_DIR."
fi

# ---------------------------------------------------------------------------
# rclone — configuração pessoal (o binário já veio na imagem)
# ---------------------------------------------------------------------------
if ask "Configurar o rclone agora (rclone config, interativo)?" "N"; then
    rclone config
fi

# ---------------------------------------------------------------------------
# DeepCool — o binário e o serviço já vieram na imagem, DESATIVADOS.
# Só ative em máquinas que realmente têm o watercooler conectado (desktop).
# ---------------------------------------------------------------------------
warn "O serviço 'deepcool-cli' já está presente nesta imagem, mas DESATIVADO por padrão."
if ask "Esta é a máquina com o watercooler DeepCool conectado (ative aqui)?" "N"; then
    sudo usermod -aG plugdev "$USER" 2>/dev/null || warn "Grupo plugdev não existe — crie com 'sudo groupadd plugdev' se necessário."
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    sudo systemctl enable --now deepcool-cli
    warn "Faça logout/login para o grupo plugdev ser aplicado."
    ok "DeepCool ativado nesta máquina."
else
    info "Serviço mantido desativado — correto para laptop ou qualquer máquina sem o hardware."
fi

# ---------------------------------------------------------------------------
# Virtualização KVM/libvirt — os pacotes já vieram na imagem. Aqui configuramos
# apenas o usuário e a rede padrão desta máquina.
# ---------------------------------------------------------------------------
if ask "Configurar virtualização KVM/libvirt para este usuário?"; then
    sudo usermod -aG libvirt "$USER"
    sudo systemctl enable --now virtqemud.socket virtnetworkd.socket

    if sudo virsh --connect qemu:///system net-info default >/dev/null 2>&1; then
        sudo virsh --connect qemu:///system net-autostart default
        if ! sudo virsh --connect qemu:///system net-info default | grep -qE '^Active:[[:space:]]+yes$'; then
            sudo virsh --connect qemu:///system net-start default
        fi
    else
        warn "A rede libvirt 'default' não foi encontrada; o virt-manager poderá criá-la posteriormente."
    fi

    warn "Faça logout/login para a associação ao grupo libvirt ser aplicada."
    ok "KVM/libvirt configurado. Abra o aplicativo Virtual Machine Manager."
fi

# ---------------------------------------------------------------------------
# Warsaw (banco) — de propósito fora da imagem. Só se esta máquina precisar.
# ---------------------------------------------------------------------------
if ask "Instalar o módulo Warsaw (Caixa) nesta máquina?" "N"; then
    warn "Feche todos os navegadores antes de continuar."
    read -rp "Pressione Enter quando tiver fechado..." _
    wget -q https://cloud.gastecnologia.com.br/cef/warsaw/install/GBPCEFwr64.rpm -O /tmp/warsaw.rpm
    sudo rpm -Uvh /tmp/warsaw.rpm
    rm -f /tmp/warsaw.rpm
    ok "Warsaw instalado."
fi

# ---------------------------------------------------------------------------
# MTU/DNS — depende da rede LOCAL de cada máquina, nunca deveria ir na imagem
# ---------------------------------------------------------------------------
if ask "Ajustar MTU/DNS da conexão cabeada desta máquina?" "N"; then
    mapfile -t ETH_CONNS < <(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-3-ethernet"{print $1}')
    if [ "${#ETH_CONNS[@]}" -eq 0 ]; then
        warn "Nenhuma conexão Ethernet encontrada."
    else
        for i in "${!ETH_CONNS[@]}"; do echo "  $((i+1))) ${ETH_CONNS[$i]}"; done
        read -rp "Qual usar? [1]: " conn_idx
        conn_idx=${conn_idx:-1}
        CONN_NAME="${ETH_CONNS[$((conn_idx-1))]}"
        nmcli connection modify "$CONN_NAME" 802-3-ethernet.mtu 1478
        nmcli connection modify "$CONN_NAME" ipv4.dns "1.1.1.1,8.8.8.8"
        nmcli connection modify "$CONN_NAME" ipv4.ignore-auto-dns yes
        nmcli connection up "$CONN_NAME"
        ok "MTU/DNS aplicados em '$CONN_NAME'."
    fi
fi

# ---------------------------------------------------------------------------
# Assistentes de IA em CLI — instalação per-user (~/.local/bin normalmente)
# ---------------------------------------------------------------------------
if ask "Instalar assistentes de IA em CLI (Claude Code, Codex, Antigravity)?" "N"; then
    curl -fsSL https://claude.ai/install.sh | bash || warn "Falha ao instalar Claude Code."
    curl -fsSL https://chatgpt.com/codex/install.sh | sh || warn "Falha ao instalar Codex."
    curl -fsSL https://antigravity.google/cli/install.sh | bash || warn "Falha ao instalar Antigravity."
    curl -fsSL https://gh.io/copilot-install | bash || warn "Falha ao instalar GitHub Copilot CLI (precisa do 'gh', já vem na imagem)."
    ok "Assistentes de IA instalados."
fi

echo
ok "Primeiro boot desta máquina configurado."
info "Tudo o resto (Steam, MangoHud, Gamescope, GameMode, Wine, VS Code, gh, fastfetch,"
info "oh-my-posh, RPM Fusion, firewalld e virt-manager/KVM) já veio pronto na própria imagem."
