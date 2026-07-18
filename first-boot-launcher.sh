#!/usr/bin/env bash
# Abre a configuração inicial interativa uma única vez por usuário/máquina.

set -euo pipefail

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}"
marker="${state_dir}/gabriel-first-boot-done"
lock_dir="${state_dir}/gabriel-first-boot-running"
setup_script="/usr/share/gabriel-dotfiles/primeiro-boot-por-maquina.sh"

mkdir -p "${state_dir}"

if [[ -e "${marker}" ]]; then
    exit 0
fi

# Evita abrir duas janelas caso o autostart seja disparado mais de uma vez.
if ! mkdir "${lock_dir}" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "${lock_dir}" 2>/dev/null || true' EXIT

if [[ ! -x "${setup_script}" ]]; then
    echo "Script de configuração não encontrado: ${setup_script}" >&2
    exit 1
fi

if ! command -v konsole >/dev/null 2>&1; then
    echo "Konsole não encontrado; execute manualmente: ${setup_script}" >&2
    exit 1
fi

export GABRIEL_FIRST_BOOT_MARKER="${marker}"
export GABRIEL_FIRST_BOOT_SCRIPT="${setup_script}"

konsole --hold -e /usr/bin/bash -lc '
    set -euo pipefail
    if "${GABRIEL_FIRST_BOOT_SCRIPT}"; then
        mkdir -p "$(dirname "${GABRIEL_FIRST_BOOT_MARKER}")"
        touch "${GABRIEL_FIRST_BOOT_MARKER}"
        printf "\nConfiguração inicial concluída. Você já pode fechar esta janela.\n"
    else
        status=$?
        printf "\nA configuração inicial terminou com erro (%s). Ela será oferecida novamente no próximo login.\n" "${status}" >&2
        exit "${status}"
    fi
'
