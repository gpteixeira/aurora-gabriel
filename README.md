# aurora-gabriel

Repositório de imagens Linux atômicas personalizadas, baseadas no ecossistema
Universal Blue/bootc. O mesmo workflow publica duas variantes:

| Imagem | Base | Foco | Registro |
|---|---|---|---|
| `aurora-custom-gpteixeira` | `ghcr.io/ublue-os/aurora-nvidia-open:stable` | KDE, desenvolvimento, gaming e VirtualBox | `ghcr.io/gpteixeira/aurora-custom-gpteixeira:latest` |
| `bazzite-gabriel` | `ghcr.io/ublue-os/bazzite-nvidia-open:stable` | Gaming Bazzite, desenvolvimento e virtualização KVM/libvirt | `ghcr.io/gpteixeira/bazzite-gabriel:latest` |

A customização é construída como imagem OCI bootável. Ela não substitui a ISO
oficial para a primeira instalação: instale uma base compatível e depois use
`bootc switch`, ou gere uma imagem de disco/ISO pelo workflow manual
**Build disk images**.

## Componentes compartilhados

As duas variantes incluem:

- ferramentas de sistema e desenvolvimento: `curl`, `git`, `gh`, `fastfetch`,
  `rclone`, `unzip`, `firewalld`, VS Code, Wine e Winetricks;
- codecs multimídia e integração com RPM Fusion já disponível nas bases;
- Oh My Posh com o tema Atomic;
- Hack Nerd Font, perfil do Konsole e configuração do fastfetch;
- `qt-deepcool`, regra udev e serviço systemd para o DeepCool MYSTIQUE;
- configuração inicial interativa por usuário, executada uma única vez pelo
  autostart do Plasma;
- validação final com `bootc container lint`.

Diferenças principais:

- **Aurora:** instala Steam, MangoHud, GameMode, Gamescope e VirtualBox.
- **Bazzite:** preserva a stack gamer da própria imagem-base, não adiciona
  GameMode e instala GNOME Boxes, QEMU/KVM, libvirt, OVMF e swtpm.

## Estrutura do repositório

- `Containerfile`: receita da variante Aurora.
- `Containerfile.bazzite`: receita da variante Bazzite.
- `Justfile`: build, tags, imagens de disco e utilitários.
- `.github/workflows/build.yml`: build em matriz, publicação no GHCR e
  assinatura cosign.
- `.github/workflows/build-disk.yml`: geração manual de QCOW2 e Anaconda ISO.
- `disk_config/`: configurações do bootc-image-builder.
- `primeiro-boot-por-maquina.sh`: perguntas e configurações dependentes do
  usuário ou da máquina.
- `first-boot-launcher.sh` e `gabriel-first-boot.desktop`: execução controlada
  do primeiro boot dentro do Plasma.

## Build local

Requisitos: Git, Podman, `just` e `jq`.

### Aurora

```bash
just build \
  aurora-custom-gpteixeira \
  latest \
  Containerfile \
  "Imagem Aurora customizada para gaming, desenvolvimento e utilitários de sistema"
```

### Bazzite

```bash
just build \
  bazzite-gabriel \
  latest \
  Containerfile.bazzite \
  "Imagem Bazzite customizada para desenvolvimento e utilitários de sistema"
```

Confirme a imagem resultante:

```bash
podman image inspect aurora-custom-gpteixeira:latest
podman image inspect bazzite-gabriel:latest
```

## Instalação com bootc

Antes da troca, confirme que a máquina usa uma variante compatível com NVIDIA
Open Kernel Modules.

### Aurora

```bash
sudo bootc switch ghcr.io/gpteixeira/aurora-custom-gpteixeira:latest
sudo reboot
```

### Bazzite

```bash
sudo bootc switch ghcr.io/gpteixeira/bazzite-gabriel:latest
sudo reboot
```

No primeiro login gráfico, o Plasma abre a configuração inicial. O marcador
`~/.local/state/gabriel-first-boot-done` impede novas execuções depois da
conclusão. Para executar novamente:

```bash
rm -f ~/.local/state/gabriel-first-boot-done
/usr/share/gabriel-dotfiles/primeiro-boot-por-maquina.sh
```

O serviço do DeepCool continua desativado por padrão. Ative apenas na máquina
que possui o hardware:

```bash
sudo systemctl enable --now deepcool-cli.service
```

## GitHub Actions

O workflow `build.yml` roda em `push` para `main`, em pull requests, diariamente
e por acionamento manual. A matriz constrói as duas imagens separadamente.

A sequência crítica é:

1. validar o `Justfile` e os arquivos usados por `COPY`;
2. executar `podman build` com o Containerfile da matriz;
3. confirmar a existência de `${IMAGE_NAME}:${DEFAULT_TAG}`;
4. criar tags de data/commit;
5. publicar no GHCR e assinar o digest.

O rechunk com rpm-ostree permanece desativado neste workflow. Isso não impede a
criação ou o uso da imagem; afeta apenas a otimização das camadas para deltas de
atualização.

## Imagens de disco e ISO

Execute manualmente **Actions → Build disk images → Run workflow** e escolha a
imagem. O workflow usa:

- `disk_config/disk.toml` para QCOW2;
- `disk_config/iso-kde.toml` para Aurora;
- `disk_config/iso-bazzite-kde.toml` para Bazzite.

Cada job publica um artefato com nome próprio, evitando colisão entre QCOW2 e
ISO.

## Assinatura cosign

A chave privada deve existir apenas no secret `SIGNING_SECRET`. A chave pública
versionada é `cosign.pub`.

```bash
cosign verify --key cosign.pub \
  ghcr.io/gpteixeira/aurora-custom-gpteixeira:latest

cosign verify --key cosign.pub \
  ghcr.io/gpteixeira/bazzite-gabriel:latest
```

## Diagnóstico rápido

### `no such object: "<imagem>:latest"` em `tag-images`

Esse erro significa que a tag esperada não existe no armazenamento local do
Podman. Verifique primeiro o passo **Build Image**. A receita atual executa o
`podman build` e valida a imagem imediatamente, portanto a falha deve aparecer
no ponto real em vez de ser adiada até a etapa de tags.

### Falha em `COPY`

Todo arquivo copiado pelos Containerfiles precisa estar no contexto do build.
O workflow valida antecipadamente os arquivos compartilhados, incluindo o
lançador e o arquivo `.desktop` do primeiro boot.

## Pontos deliberadamente externos à imagem

Rustup, Flutter SDK, configurações pessoais do rclone, Warsaw, ajustes locais
de MTU/DNS e assistentes de IA em CLI são tratados pelo script de primeiro
boot, pois vivem no `$HOME`, dependem da máquina ou exigem decisão explícita do
usuário.
