# =============================================================================
# Containerfile — imagem customizada baseada no Aurora (Universal Blue)
#
# Este arquivo NÃO gera uma ISO. Ele constrói a IMAGEM que seu sistema vai
# seguir depois que você rodar "bootc switch" nele uma vez (veja README.md).
#
# Filosofia adotada aqui:
#   - Coisas de SISTEMA (drivers, pacotes, serviços) ficam neste Containerfile.
#   - Coisas de USUÁRIO (Rust via rustup, Flutter em ~/development, configs
#     pessoais) ficam no script "primeiro-boot-por-maquina.sh", porque
#     precisam viver em /home, que NÃO faz parte da imagem.
#   - Coisas SENSÍVEIS (Warsaw/banco) ficam de fora de propósito — não é
#     boa prática misturar credencial/software financeiro com uma imagem
#     compilada automaticamente e versionada publicamente.
# =============================================================================

# Confira o nome exato da tag em https://github.com/orgs/ublue-os/packages
# antes de usar em produção — troque para a variante "-nvidia-open" se ela
# existir separadamente (sua RTX 5080 precisa do módulo aberto da NVIDIA).
FROM ghcr.io/ublue-os/aurora:stable AS base

# Garante que falhas dentro de "curl ... | bash" (como nos instaladores do
# oh-my-posh e rclone mais abaixo) realmente quebrem o build, em vez de
# passar batido silenciosamente se o curl falhar mas o bash ainda "rodar".
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# 1) RPM Fusion + codecs completos (ffmpeg de verdade, não o ffmpeg-free)
#
#    Nota: "dnf group upgrade multimedia" foi trocado por pacotes explícitos.
#    Dentro de um build de container, os metadados de grupo (comps) nem
#    sempre estão disponíveis da mesma forma que num sistema já instalado —
#    isso já quebrou um build nosso com "No match for argument: multimedia".
#    Instalar os pacotes diretamente evita depender desses metadados opcionais.
# -----------------------------------------------------------------------------
RUN dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
    && dnf swap -y ffmpeg-free ffmpeg --allowerasing \
    && dnf config-manager setopt fedora-cisco-openh264.enabled=1 \
    && dnf install -y \
        openh264 gstreamer1-plugin-openh264 \
        gstreamer1-plugins-ugly gstreamer1-plugins-bad-freeworld gstreamer1-libav \
        libfdk-aac.x86_64 libfdk-aac.i686 \
    && dnf clean all
# Nota: libfdk-aac.i686 explícito evita um bug antigo do RPM/DNF em que o
# "Obsoletes" do libfdk-aac de 64 bits bloqueia a instalação da versão de
# 32 bits (fdk-aac-free.i686) que o Steam precisa para a pilha de áudio
# pipewire de 32 bits — mesmo sendo arquiteturas diferentes. Sem isso, o
# "dnf install steam" da próxima etapa falha com um conflito de dependências.

# -----------------------------------------------------------------------------
# 2) Stack de gaming (Steam, MangoHud, GameMode, Gamescope, Wine)
# -----------------------------------------------------------------------------
RUN dnf install -y \
        steam mangohud gamemode gamescope wine winetricks vulkan-tools \
    && dnf clean all

# -----------------------------------------------------------------------------
# 3) Ferramentas de sistema (VS Code, GitHub CLI, fastfetch, oh-my-posh, rclone)
# -----------------------------------------------------------------------------
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc \
    && printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' \
        > /etc/yum.repos.d/vscode.repo \
    && dnf install -y dnf5-plugins \
    && dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo \
    && dnf install -y code gh fastfetch \
    && dnf clean all

# oh-my-posh e rclone: binário único, instalados globalmente em /usr/local/bin
# (os temas/configs pessoais do oh-my-posh continuam ficando em ~/.config,
# por usuário, no primeiro boot — só o binário mora aqui).
RUN curl -s https://ohmyposh.dev/install.sh | bash -s -- -d /usr/local/bin \
    && curl https://rclone.org/install.sh | bash

# Tema "Atomic" do oh-my-posh, fixado como padrão para QUALQUER usuário desta
# imagem. Diferente do Konsole/fastfetch (que dependem de $HOME e por isso
# precisam do script de primeiro boot), o prompt do bash é configurado via
# /etc/profile.d/ — um script ali roda automaticamente pra todo mundo que
# abrir um shell de login, sem precisar copiar nada pra pasta de ninguém.
# Usamos o arquivo baixado localmente (não a URL remota) por recomendação da
# própria documentação do oh-my-posh: evita depender de rede toda vez que um
# terminal abre, e é mais rápido.
RUN mkdir -p /usr/local/share/oh-my-posh/themes \
    && curl -sL https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/atomic.omp.json \
        -o /usr/local/share/oh-my-posh/themes/atomic.omp.json
RUN printf '#!/bin/bash\nif [ -t 1 ] && command -v oh-my-posh &> /dev/null; then\n    eval "$(oh-my-posh init bash --config /usr/local/share/oh-my-posh/themes/atomic.omp.json)"\nfi\n' \
        > /etc/profile.d/gabriel-oh-my-posh.sh \
    && chmod +x /etc/profile.d/gabriel-oh-my-posh.sh

# Fonte Hack Nerd Font, instalada globalmente (system-wide) — equivalente ao
# "oh-my-posh font install hack", mas de forma que funciona pra qualquer
# usuário da imagem, não só quem rodar o instalador depois.
RUN mkdir -p /usr/share/fonts/hack-nerd-font \
    && curl -sL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip \
        -o /tmp/hack-nerd-font.zip \
    && unzip -o /tmp/hack-nerd-font.zip -d /usr/share/fonts/hack-nerd-font \
    && rm -f /tmp/hack-nerd-font.zip /usr/share/fonts/hack-nerd-font/*Windows* \
    && fc-cache -f

# -----------------------------------------------------------------------------
# 3.1) Dotfiles "modelo" — Konsole (Dark Pastels + Hack Nerd Font) e fastfetch.
#      Ficam guardados como TEMPLATE dentro da imagem, em /usr/share/. O
#      script de primeiro boot (primeiro-boot-por-maquina.sh) copia esses
#      arquivos para dentro do $HOME do usuário de verdade — porque $HOME
#      fica FORA da imagem, e uma conta já existente não é populada por
#      /etc/skel (que só vale para contas novas).
# -----------------------------------------------------------------------------
RUN mkdir -p /usr/share/gabriel-dotfiles/konsole /usr/share/gabriel-dotfiles/fastfetch
COPY DarkPastels.colorscheme /usr/share/gabriel-dotfiles/konsole/DarkPastels.colorscheme
COPY Gabriel.profile /usr/share/gabriel-dotfiles/konsole/Gabriel.profile
COPY fastfetch-config.jsonc /usr/share/gabriel-dotfiles/fastfetch/config.jsonc
# Também deixamos uma cópia em /etc/skel, para contas NOVAS criadas a partir
# desta imagem já nascerem com tudo pronto, sem precisar do script:
RUN mkdir -p /etc/skel/.local/share/konsole /etc/skel/.config/fastfetch
COPY DarkPastels.colorscheme /etc/skel/.local/share/konsole/DarkPastels.colorscheme
COPY Gabriel.profile /etc/skel/.local/share/konsole/Gabriel.profile
COPY fastfetch-config.jsonc /etc/skel/.config/fastfetch/config.jsonc
RUN printf '[Desktop Entry]\nDefaultProfile=Gabriel.profile\n' > /etc/skel/.config/konsolerc

# -----------------------------------------------------------------------------
# 4) Virtualização (GNOME Boxes / QEMU / KVM / libvirt)
#    Se o Aurora já trouxer isso por padrão, este passo é apenas idempotente.
# -----------------------------------------------------------------------------
RUN dnf install -y "@virtualization" gnome-boxes \
    && dnf clean all

# -----------------------------------------------------------------------------
# 5) Firewall — política padrão (nega entrada, libera saída)
#    firewall-offline-cmd é a ferramenta certa para configurar firewalld
#    DURANTE o build de uma imagem (não há systemd rodando de verdade aqui,
#    então "firewall-cmd" normal não funcionaria).
# -----------------------------------------------------------------------------
RUN firewall-offline-cmd --set-default-zone=drop \
    && firewall-offline-cmd --zone=drop --add-service=dhcpv6-client

# -----------------------------------------------------------------------------
# 6) qt-deepcool — compilado em estágio separado, binário final copiado pra
#    imagem definitiva sem carregar todo o toolchain de build junto.
#    O serviço fica PRESENTE mas NUNCA habilitado aqui — cada máquina decide
#    (veja README.md: só o desktop com o watercooler deve ativá-lo).
# -----------------------------------------------------------------------------
FROM fedora:44 AS deepcool-builder
RUN dnf install -y cmake gcc-c++ qt6-qtbase-devel libusb1-devel systemd-devel git \
    && git clone https://github.com/mymymy1303/qt-deepcool.git /src \
    && cmake -B /src/build -S /src \
    && cmake --build /src/build

FROM base
COPY --from=deepcool-builder /src/build/bin/deepcool-cli /usr/local/bin/deepcool-cli
COPY --from=deepcool-builder /src/99-deepcool.rules /etc/udev/rules.d/99-deepcool.rules
COPY deepcool-cli.service /etc/systemd/system/deepcool-cli.service
# Repare: NÃO há "RUN systemctl enable deepcool-cli" aqui — fica desativado
# por padrão em toda máquina que usar esta imagem, de propósito.

# -----------------------------------------------------------------------------
# Metadados finais (opcional, mas ajuda a rastrear qual build gerou o quê)
# -----------------------------------------------------------------------------
LABEL org.opencontainers.image.title="aurora-gabriel"
LABEL org.opencontainers.image.description="Imagem Aurora customizada — stack pessoal de gaming, dev e utilitários de sistema"
