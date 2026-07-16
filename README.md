# aurora-custom-gpteixeira

Imagem Aurora (Universal Blue) customizada — bootc/OCI. Este documento
descreve exatamente o que a imagem faz e como usá-la. Para tudo que for
específico do **Aurora em si** (o que ele é, filosofia do projeto, como o
sistema atômico funciona por baixo), a fonte oficial é:

- **Documentação oficial do Aurora**: <https://docs.getaurora.dev>
- **Repositório oficial do Aurora**: <https://github.com/ublue-os/aurora>
- **Universal Blue** (projeto guarda-chuva): <https://universal-blue.org>

Este README cobre só a **camada customizada** por cima dessa base.

---

## O que esta imagem NÃO é

Não gera uma ISO. Ela é uma **imagem de container bootc**, publicada no
GHCR. Você instala o Aurora oficial (ISO padrão) e depois troca pra esta
imagem com um único comando (`bootc switch`) — a partir daí, toda
atualização futura já vem da sua receita, automaticamente.

---

## O que está incluído na imagem (por seção do `Containerfile`)

### 0) Compilação isolada do `qt-deepcool`
Compilado num estágio `fedora:44` separado (não fica no sistema final,
só o binário resultante é copiado). Controla a tela do watercooler
DeepCool MYSTIQUE. Referência configurável via `QT_DEEPCOOL_REF`
(padrão: `main`; use um commit específico para builds 100% reprodutíveis).

### 1) Imagem-base
`ghcr.io/ublue-os/aurora-nvidia-open:stable` — Aurora (KDE Plasma) com o
driver **NVIDIA de código aberto** já embutido, adequado para a RTX 5080.
Confira `sudo bootc status` na máquina de destino para garantir que essa é
a variante certa antes de trocar.

### 2) Dependências base
`curl`, `git`, `gh`, `fastfetch`, `rclone`, `unzip`, `firewalld`,
`qt6-qtbase`, `libusb1`, entre outras — ferramentas de sistema usadas pelo
resto da imagem ou no dia a dia.

### 3) RPM Fusion + codecs multimídia
Habilita RPM Fusion (free + nonfree). Faz uma checagem condicional antes de
trocar `ffmpeg-free` por `ffmpeg` completo (evita erro caso o Aurora já
tenha o ffmpeg completo por padrão). Habilita o repositório
`fedora-cisco-openh264` e instala os plugins GStreamer necessários para
H.264 e outros codecs. Instala `libfdk-aac` nas **duas arquiteturas**
(x86_64 e i686) de propósito — evita um bug antigo do RPM/DNF em que o
`Obsoletes` da versão de 64 bits bloqueia a versão de 32 bits que o Steam
precisa.

### 4) Stack de gaming
Steam, MangoHud, GameMode, Gamescope, Wine, Winetricks, Vulkan Tools.

### 5) Visual Studio Code
Repositório oficial da Microsoft, chave GPG importada explicitamente para
`/etc/pki/rpm-gpg/`.

### 6) Oh My Posh
Binário baixado com versão fixada (`OH_MY_POSH_VERSION`), instalado em
`/usr/bin` (não `/usr/local` — em sistemas bootc, `/usr/local` aponta para
`/var/usrlocal`, que é estado da máquina, não da imagem). Tema **Atomic**
baixado e fixado localmente em `/usr/share/oh-my-posh/themes/`. Um script
em `/etc/profile.d/gabriel-oh-my-posh.sh` ativa o tema automaticamente para
qualquer usuário que abrir um shell de login — sem precisar de passo extra
no primeiro boot.

### 7) Hack Nerd Font
Baixada com versão fixada (`NERD_FONTS_VERSION`) e instalada globalmente em
`/usr/share/fonts/`.

### 8) Dotfiles-modelo (Konsole + fastfetch)
`DarkPastels.colorscheme` (esquema de cores do Konsole, 5% de
transparência), `Gabriel.profile` (perfil apontando pra esse esquema +
Hack Nerd Font 11pt) e `fastfetch-config.jsonc` ficam guardados em
`/usr/share/gabriel-dotfiles/` (para o script de primeiro boot aplicar em
contas já existentes) **e** em `/etc/skel/` (para contas novas criadas a
partir desta imagem já nascerem configuradas).

### 9) Virtualização
GNOME Boxes, QEMU/KVM, libvirt, `swtpm` (TPM emulado — necessário para
instalar Windows 11 em VM), `edk2-ovmf` (firmware UEFI para VMs).

### 10) Firewall
Política padrão nega entrada, libera saída — aplicada com
`firewall-offline-cmd`, já que não há `systemd` rodando de verdade durante
o build de uma imagem.

### 11) qt-deepcool — binário final
Binário copiado do estágio de build para `/usr/bin/deepcool-cli`. Regra de
udev copiada para `/etc/udev/rules.d/`. O serviço systemd é copiado mas
**nunca habilitado** na imagem — cada máquina decide, manualmente, se quer
ativá-lo:

```bash
sudo systemctl enable --now deepcool-cli.service
```

Use isso **só** na máquina que tem o watercooler conectado de verdade
(o desktop). Em qualquer outra máquina (como o laptop), deixe desativado.

### 12-13) Metadados e validação
Labels OCI padrão, e `bootc container lint` — validação oficial do próprio
projeto bootc, roda como última etapa do build e falha o build se algo
estiver estruturalmente errado com a imagem.

---

## O que fica DE FORA da imagem (de propósito)

| Item | Por quê | Onde vive |
|---|---|---|
| Rust (`rustup`), Flutter SDK | Precisam morar em `$HOME`, fora da imagem | `primeiro-boot-por-maquina.sh` |
| MTU/DNS da conexão | Depende da rede física de cada máquina | `primeiro-boot-por-maquina.sh` |
| Ativação do `deepcool-cli` | Só faz sentido na máquina com o hardware | Comando manual, uma vez, na máquina certa |

---

## Como usar

### 1. Instale o Aurora oficial primeiro
Baixe a ISO oficial em <https://getaurora.dev> e instale normalmente — sem
nenhuma customização ainda. Nada de especial nesse passo.

> **Nota sobre testes em VM**: se for testar esta imagem numa VM (GNOME
> Boxes, por exemplo), a variante `aurora-nvidia-open` funciona sem
> travar — o driver NVIDIA simplesmente não encontra uma GPU real e não
> carrega, sem quebrar o sistema. Mas ela baixa ~1-2 GB de driver que não
> serve pra nada dentro da VM. Se quiser um teste mais leve e focado só na
> customização (tema, apps, dev tools), use a variante sem NVIDIA
> (`ghcr.io/ublue-os/aurora:stable`) pra instalar a ISO base na VM.

### 2. Troque para esta imagem customizada
```bash
sudo bootc switch ghcr.io/gpteixeira/aurora-custom-gpteixeira:latest
sudo reboot
```

### 3. Rode o script de primeiro boot (por máquina)
```bash
bash primeiro-boot-por-maquina.sh
```

Isso cobre Rust, Flutter, aplicação dos dotfiles no seu usuário (que já
existia antes do `bootc switch`, então não foi alcançado por `/etc/skel`),
e pergunta se aquela máquina específica deve ativar o `deepcool-cli`.

---

## Segurança da imagem (assinatura cosign)

Todo build é assinado com `cosign`. Para verificar a assinatura de uma
imagem publicada:

```bash
cosign verify --key cosign.pub ghcr.io/gpteixeira/aurora-custom-gpteixeira:latest
```

A chave privada de assinatura fica só no GitHub Secret (`SIGNING_SECRET`),
nunca no repositório. Só o `cosign.pub` (chave pública) é versionado.

---

## Atualizações automáticas

O workflow de build roda:
- **Automaticamente**, todo dia (agendado via `cron` em
  `.github/workflows/build.yml` — horário em UTC, ajuste conforme
  necessário para seu fuso).
- **A cada `git push`** na branch `main`, imediatamente.
- **Manualmente**, a qualquer momento, pelo botão "Run workflow" na aba
  Actions (precisa de `workflow_dispatch:` habilitado no workflow).

A imagem sempre baixa a versão mais recente do Aurora (`--pull=newer`) no
momento do build — não existe "aviso" de quando o Aurora publica algo
novo; é reconstrução periódica que garante isso na prática.

No seu PC, o `bootc-fetch-apply-updates.timer` verifica periodicamente se
a imagem publicada mudou e prepara a atualização para o próximo boot —
sem aplicar nada sem você reiniciar quando quiser.

---

## Testando antes de aplicar numa máquina real

```bash
just build
just build-qcow2
just run-vm-qcow2
```

Builda localmente e sobe uma VM a partir da imagem, sem depender do
GitHub Actions nem arriscar uma máquina real.

---

## Segurança do repositório

Para garantir que nenhum commit chegue à branch `main` sem sua autorização
explícita (incluindo PRs automáticos do Dependabot):

**Settings → Branches → Add rule** para `main`, marque **"Restrict who can
push to matching branches"** e liste apenas seu usuário. Opcionalmente,
em **Settings → General → Pull Requests**, confirme que **"Allow
auto-merge"** está desmarcado.

