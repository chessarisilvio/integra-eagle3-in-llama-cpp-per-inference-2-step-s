#!/usr/bin/env bash
# run-eagle3.sh
# Avvia llama.cpp con EAGLE3 distribuendo modello principale su Tesla P40 (GPU 1)
# e modello helper su RTX 3050 (GPU 0).
# Rispetta la privacy: usa solo path relativi o variabili d'ambiente.

set -euo pipefail

# === Configurazione ===
# Directory dello script (funziona anche se chiamato da altrove)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Nome eseguibile llama.cpp (può essere sovrascritto)
LLAMA_BIN="${LLAMA_BIN:-./llama-cli}"

# Percorsi modello (sovrascrivibili via env)
MODEL_MAIN="${MODEL_PATH_MAIN:-./models/main_model.gguf}"
MODEL_HELPER="${MODEL_PATH_HELPER:-./models/helper_model.gguf}"

# File di log
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/eagle3_$(date +%Y%m%d_%H%M%S).log"

# Opzioni EAGLE3 (da config/settings.json)
EAGLE3_MAIN_GPU=1   # Tesla P40
EAGLE3_HELPER_GPU=0 # RTX 3050

# Altri argomenti utili (personalizzabili)
CTX_SIZE="${CTX_SIZE:-8192}"
BATCH_SIZE="${BATCH_SIZE:-512}"
THREADS="${THREADS:-4}"
NGL_MAIN="${NGL_MAIN:-99}"   # numero layer da offloadare sulla GPU principale
NGL_HELPER="${NGL_HELPER:-99}" # sul helper (di solito meno)

# === Funzioni di supporto ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERRORE: $*" >&2
    exit 1
}

check_file() {
    if [[ ! -f "$1" ]]; then
        error "File non trovato: $1"
    fi
}

# === Verifiche preliminari ===
log "Avvio script EAGLE3 inference 2-step"
log "Directory lavoro: $SCRIPT_DIR"

# Controlla eseguibile
if [[ ! -x "$LLAMA_BIN" ]]; then
    error "Eseguibile llama.cpp non trovato o non eseguibile: $LLAMA_BIN"
fi
log "Usa eseguibile: $LLAMA_BIN"

# Controlla modelli
check_file "$MODEL_MAIN"
check_file "$MODEL_HELPER"
log "Modello principale: $MODEL_MAIN"
log "Modello helper: $MODEL_HELPER"

# Crea directory log
mkdir -p "$LOG_DIR"

# === Costruisci comando llama.cpp ===
# Nota: le opzioni esatte possono variare a seconda della versione di llama.cpp.
# Si basa su tipiche opzioni per EAGLE3 (vedi documentazione llama.cpp).
CMD=(
    "$LLAMA_BIN"
    "-m" "$MODEL_MAIN"
    "--model" "$MODEL_HELPER"          # secondo modello per EAGLE3
    "--eagle3"
    "--split-mode" "layer"             # o 'row' a seconda del supporto
    "--main-gpu" "$EAGLE3_MAIN_GPU"
    "--helper-gpu" "$EAGLE3_HELPER_GPU"
    "--ctx-size" "$CTX_SIZE"
    "--batch-size" "$BATCH_SIZE"
    "--threads" "$THREADS"
    "--ngl" "$NGL_MAIN"                # offload main model
    # Per il helper potrebbe essere necessario un secondo --ngl? Alcune versioni usano --helper-ngl
    # Aggiungiamo se supportato:
    # "--helper-ngl" "$NGL_HELPER"
    # Log di debug
    "--log-disable"    # disabilita log interno di llama.cpp, noi gestiamo il nostro
)

# Aggiungi eventuali argomenti extra passati allo script
ARGS=("$@")
if [[ ${#ARGS[@]} -gt 0 ]]; then
    log "Argomenti aggiuntivi: ${ARGS[*]}"
    CMD+=("${ARGS[@]}")
fi

log "Esecuzione comando: ${CMD[*]}"
# Esegui e logga output
"${CMD[@]}" 2>&1 | tee -a "$LOG_FILE"

# Controlla stato di uscita
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    error "llama.cpp è terminato con errore (vedi log sopra)"
else
    log "Inference completata con successo"
fi