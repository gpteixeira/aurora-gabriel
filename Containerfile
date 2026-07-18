# =============================================================================
# Containerfile — imagem customizada baseada no Aurora (Universal Blue)
#
# Este arquivo NÃO gera uma ISO. Ele constrói uma imagem OCI/bootc que poderá
# ser usada com "bootc switch".
#
# Organização:
#   - Sistema, drivers, pacotes e serviços: nesta imagem.
#   - Configurações e ferramentas que precisam viver em /home: script de
#     primeiro boot por máquina.
#   - Aplicativos com dados sensíveis ou uso bancário: fora da imagem.
#
# Arquivos esperados no contexto do build:
#   - DarkPastels.colorscheme
#   - Gabriel.profile
#   - fastfetch-config.jsonc
#   - deepcool-cli.service
# =============================================================================


# -----------------------------------------------------------------------------
# 0) Builder isolado do qt-deepcool
#
# Para máxima reprodutibilidade, substitua "main" por um commit específico:
#   podman build --build-arg QT_DEEPCOOL_REF=<commit> ...
# -----------------------------------------------------------------------------
FROM fedora:44 AS deepcool-builder

ARG QT_DEEPCOOL_REF=main

RUN dnf5 install -y \
        cmake \
        gcc-c++ \
        git \
        libusb1-devel \
        pkgconf-pkg-config \
        qt6-qtbase-devel \
        systemd-devel \
    && dnf5 clean all

RUN git clone https://github.com/mymymy1303/qt-deepcool.git /src \
    && git -C /src checkout "${QT_DEEPCOOL_REF}" \
    && cmake \
        -S /src \
        -B /src/build \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /src/build --parallel "$(nproc)" \
    && cmake --install /src/build \
        --prefix /usr/local \
        --strip


# -----------------------------------------------------------------------------
# 1) Imagem-base
#
# A variante nvidia-open é adequada para a máquina com NVIDIA RTX 5080.
# Caso a máquina de destino use outra variante do Aurora, ajuste este FROM
# para corresponder à imagem exibida por:
#
#   sudo bootc status
# -----------------------------------------------------------------------------
FROM ghcr.io/ublue-os/aurora-nvidia-open:stable AS final

ARG OH_MY_POSH_VERSION=29.26.1
ARG NERD_FONTS_VERSION=3.4.0


# -----------------------------------------------------------------------------
# 2) Dependências fundamentais da customização
#
# Não usamos a instrução SHELL, pois o Podman em formato OCI a ignora.
# Quando pipefail é necessário, o Bash é chamado explicitamente.
# -----------------------------------------------------------------------------
RUN dnf5 install -y \
        ca-certificates \
        curl \
        dnf5-plugins \
        firewalld \
        fontconfig \
        fastfetch \
        git \
        gh \
        libusb1 \
        qt6-qtbase \
        rclone \
        unzip \
    && dnf5 clean all


# -----------------------------------------------------------------------------
# 3) RPM Fusion e codecs multimídia
#
# O Aurora normalmente já traz o ffmpeg completo. Esta verificação evita que
# "dnf5 swap ffmpeg-free ffmpeg" falhe quando ffmpeg já estiver instalado.
# -----------------------------------------------------------------------------
RUN /bin/bash -c 'set -euxo pipefail; \
    if rpm -q ffmpeg-free >/dev/null 2>&1; then \
        echo "ffmpeg-free encontrado; realizando a troca por ffmpeg."; \
        dnf5 swap -y ffmpeg-free ffmpeg --allowerasing; \
    elif rpm -q ffmpeg >/dev/null 2>&1; then \
        echo "ffmpeg completo já está instalado; nenhuma troca necessária."; \
    else \
        echo "Nenhum ffmpeg encontrado; instalando o pacote completo."; \
        dnf5 install -y ffmpeg --allowerasing; \
    fi; \
    dnf5 config-manager setopt fedora-cisco-openh264.enabled=1; \
    dnf5 install -y \
        openh264 \
        gstreamer1-plugin-openh264 \
        gstreamer1-plugins-ugly \
        gstreamer1-plugins-bad-freeworld \
        gstreamer1-libav \
        libfdk-aac.x86_64 \
        libfdk-aac.i686; \
    dnf5 clean all'


# -----------------------------------------------------------------------------
# 4) Stack de gaming
# -----------------------------------------------------------------------------
RUN dnf5 install -y \
        gamemode \
        gamescope \
        mangohud \
        steam \
        vulkan-tools \
        wine \
        winetricks \
    && dnf5 clean all


# -----------------------------------------------------------------------------
# 5) Visual Studio Code
#
# O GitHub CLI é instalado do repositório do Fedora, sem adicionar um segundo
# repositório externo. O VS Code permanece no repositório oficial da Microsoft.
# -----------------------------------------------------------------------------
RUN /bin/bash -c 'set -euxo pipefail; \
    curl -fsSL \
        https://packages.microsoft.com/keys/microsoft.asc \
        -o /tmp/microsoft.asc; \
    install -Dm0644 \
        /tmp/microsoft.asc \
        /etc/pki/rpm-gpg/RPM-GPG-KEY-microsoft; \
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-microsoft; \
    printf "%s\n" \
        "[code]" \
        "name=Visual Studio Code" \
        "baseurl=https://packages.microsoft.com/yumrepos/vscode" \
        "enabled=1" \
        "gpgcheck=1" \
        "repo_gpgcheck=0" \
        "gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-microsoft" \
        > /etc/yum.repos.d/vscode.repo; \
    dnf5 install -y code; \
    rm -f /tmp/microsoft.asc; \
    dnf5 clean all'


# -----------------------------------------------------------------------------
# 6) Oh My Posh
#
# Em imagens Atomic/bootc, /usr/local aponta para /var/usrlocal. Como /var é
# estado persistente da máquina e não pertence à composição atualizável da
# imagem, binários fornecidos por esta imagem devem ficar em /usr/bin e seus
# dados compartilhados em /usr/share.
#
# O download é feito primeiro em /tmp e somente depois instalado no destino.
# Isso evita deixar um binário parcial caso a transferência falhe.
# -----------------------------------------------------------------------------
RUN /bin/bash -c 'set -euxo pipefail; \
    curl \
        --fail \
        --show-error \
        --location \
        --retry 3 \
        --retry-all-errors \
        "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v${OH_MY_POSH_VERSION}/posh-linux-amd64" \
        -o /tmp/oh-my-posh; \
    install -Dm0755 \
        /tmp/oh-my-posh \
        /usr/bin/oh-my-posh; \
    install -d -m 0755 \
        /usr/share/oh-my-posh/themes; \
    curl \
        --fail \
        --show-error \
        --location \
        --retry 3 \
        --retry-all-errors \
        "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/v${OH_MY_POSH_VERSION}/themes/atomic.omp.json" \
        -o /tmp/atomic.omp.json; \
    install -Dm0644 \
        /tmp/atomic.omp.json \
        /usr/share/oh-my-posh/themes/atomic.omp.json; \
    rm -f \
        /tmp/oh-my-posh \
        /tmp/atomic.omp.json; \
    /usr/bin/oh-my-posh version'

RUN printf '%s\n' \
        '#!/bin/bash' \
        'if [ -n "${BASH_VERSION:-}" ] && [ -t 1 ] && command -v oh-my-posh >/dev/null 2>&1; then' \
        '    eval "$(oh-my-posh init bash --config /usr/share/oh-my-posh/themes/atomic.omp.json)"' \
        'fi' \
        > /etc/profile.d/gabriel-oh-my-posh.sh \
    && chmod 0755 /etc/profile.d/gabriel-oh-my-posh.sh


# -----------------------------------------------------------------------------
# 7) Hack Nerd Font
# -----------------------------------------------------------------------------
RUN /bin/bash -c 'set -euxo pipefail; \
    install -d -m 0755 /usr/share/fonts/hack-nerd-font; \
    curl -fsSL \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/Hack.zip" \
        -o /tmp/hack-nerd-font.zip; \
    unzip -q -o \
        /tmp/hack-nerd-font.zip \
        -d /usr/share/fonts/hack-nerd-font; \
    rm -f \
        /tmp/hack-nerd-font.zip \
        /usr/share/fonts/hack-nerd-font/*Windows*; \
    fc-cache -f'


# -----------------------------------------------------------------------------
# 8) Dotfiles modelo — Konsole e fastfetch
#
# Uma cópia fica em /usr/share para o script de primeiro boot aplicar às contas
# existentes. Outra fica em /etc/skel para contas criadas futuramente.
# -----------------------------------------------------------------------------
RUN install -d -m 0755 \
        /usr/share/gabriel-dotfiles/konsole \
        /usr/share/gabriel-dotfiles/fastfetch \
        /etc/skel/.local/share/konsole \
        /etc/skel/.config/fastfetch

COPY DarkPastels.colorscheme \
    /usr/share/gabriel-dotfiles/konsole/DarkPastels.colorscheme
COPY Gabriel.profile \
    /usr/share/gabriel-dotfiles/konsole/Gabriel.profile
COPY fastfetch-config.jsonc \
    /usr/share/gabriel-dotfiles/fastfetch/config.jsonc

COPY DarkPastels.colorscheme \
    /etc/skel/.local/share/konsole/DarkPastels.colorscheme
COPY Gabriel.profile \
    /etc/skel/.local/share/konsole/Gabriel.profile
COPY fastfetch-config.jsonc \
    /etc/skel/.config/fastfetch/config.jsonc

RUN printf '%s\n' \
        '[Desktop Entry]' \
        'DefaultProfile=Gabriel.profile' \
        > /etc/skel/.config/konsolerc


# -----------------------------------------------------------------------------
# 8.1) Configuração inicial automática, uma vez por usuário/máquina
# -----------------------------------------------------------------------------
COPY primeiro-boot-por-maquina.sh \
    /usr/share/gabriel-dotfiles/primeiro-boot-por-maquina.sh
COPY first-boot-launcher.sh \
    /usr/share/gabriel-dotfiles/first-boot-launcher.sh
COPY gabriel-first-boot.desktop \
    /etc/xdg/autostart/gabriel-first-boot.desktop

RUN chmod 0755 \
        /usr/share/gabriel-dotfiles/primeiro-boot-por-maquina.sh \
        /usr/share/gabriel-dotfiles/first-boot-launcher.sh \
    && chmod 0644 /etc/xdg/autostart/gabriel-first-boot.desktop


# -----------------------------------------------------------------------------
# 9) Virtualização — VirtualBox
#
# RPM Fusion já foi habilitado na Seção 3 (codecs) — não precisa repetir
# aqui. akmod-VirtualBox compila o módulo de kernel vboxdrv contra o kernel
# desta imagem no momento do build.
# -----------------------------------------------------------------------------
RUN dnf5 install -y \
        akmod-VirtualBox \
        VirtualBox \
    && dnf5 clean all


# -----------------------------------------------------------------------------
# 10) Firewall
#
# Durante o build não há um systemd funcional. Por isso, a política é gravada
# com firewall-offline-cmd.
# -----------------------------------------------------------------------------
RUN /bin/bash -c 'set -euxo pipefail; \
    firewall-offline-cmd --set-default-zone=drop; \
    if ! firewall-offline-cmd \
        --zone=drop \
        --query-service=dhcpv6-client; then \
        firewall-offline-cmd \
            --zone=drop \
            --add-service=dhcpv6-client; \
    fi'


# -----------------------------------------------------------------------------
# 11) qt-deepcool
#
# O binário é compilado no estágio separado. A regra udev e o serviço são
# copiados, mas o serviço NÃO é habilitado globalmente.
#
# Na máquina que possui o watercooler:
#   sudo systemctl enable --now deepcool-cli.service
# -----------------------------------------------------------------------------
COPY --from=deepcool-builder \
    /usr/local/bin/deepcool-cli \
    /usr/bin/deepcool-cli

COPY --from=deepcool-builder \
    /src/99-deepcool.rules \
    /etc/udev/rules.d/99-deepcool.rules

COPY deepcool-cli.service \
    /etc/systemd/system/deepcool-cli.service

RUN chmod 0755 /usr/bin/deepcool-cli \
    && chmod 0644 \
        /etc/udev/rules.d/99-deepcool.rules \
        /etc/systemd/system/deepcool-cli.service


# -----------------------------------------------------------------------------
# 12) Metadados OCI
#
# O workflow do image-template acrescentará os metadados relacionados ao
# repositório, commit e data do build.
# -----------------------------------------------------------------------------
LABEL org.opencontainers.image.title="aurora-custom-gpteixeira" \
      org.opencontainers.image.description="Imagem Aurora customizada para gaming, desenvolvimento e utilitários de sistema" \
      org.opencontainers.image.base.name="ghcr.io/ublue-os/aurora-nvidia-open:stable"


# -----------------------------------------------------------------------------
# 13) Validação final bootc
# -----------------------------------------------------------------------------
RUN bootc container lint
