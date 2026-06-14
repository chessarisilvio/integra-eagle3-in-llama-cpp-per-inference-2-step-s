#!/usr/bin/env bash
# benchmark-manuale.sh
# Script di benchmark manuale per EAGLE3 su P40+3050.
# Misura tok/s, latenza e VRAM quando le GPU sono libere.
# RICHIEDE INTERVENTO MANUALE: assicurarsi che le GPU siano libere prima di eseguire.
# Usa solo path relativi o variabili d'ambiente per rispettare la privacy.

set -euo pipefail

# Directory dello script (funziona anche se chiamato da altrove)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Carica configurazione da config/settings.json se esiste
if [[ -f "config/settings.json" ]]; then
    # Estrai valori di default (se non sovrascritti da env)
    # Nota: questo è un parsing semplice, per produzione si potrebbe usare jq o simili.
    # Ma per evitare dipendenze, usiamo grep e sed con cautela.
    MODEL_PATH_MAIN_DEFAULT=$(grep -o '"model_path_default": *"[^"]*"' config/settings.json | grep -o '"[^"]*"$' | sed 's/"//g' | head -1)
    MODEL_PATH_HELPER_DEFAULT=$(grep -o '"model_path_default": *"[^"]*"' config/settings.json | grep -o '"[^"]*"$' | sed 's/"//g' | tail -1)
    MAIN_GPU_DEFAULT=$(grep -o '"gpu_index": *[0-9]*' config/settings.json | grep -o '[0-9]*' | head -1)
    HELPER_GPU_DEFAULT=$(grep -o '"gpu_index": *[0-9]*' config/settings.json | grep -o '[0-9]*' | tail -1)
else
    # Fallback se il file config non esiste
    MODEL_PATH_MAIN_DEFAULT="./models/main_model.gguf"
    MODEL_PATH_HELPER_DEFAULT="./models/helper_model.gguf"
    MAIN_GPU_DEFAULT=1
    HELPER_GPU_DEFAULT=0
fi

# Sovrascrivibili via variabili d'ambiente
MODEL_PATH_MAIN="${MODEL_PATH_MAIN:-$MODEL_PATH_MAIN_DEFAULT}"
MODEL_PATH_HELPER="${MODEL_PATH_HELPER:-$MODEL_PATH_HELPER_DEFAULT}"
MAIN_GPU="${MAIN_GPU:-$MAIN_GPU_DEFAULT}"
HELPER_GPU="${HELPER_GPU:-$HELPER_GPU_DEFAULT}"

# Nome eseguibile llama.cpp (può essere sovrascritto)
LLAMA_BIN="${LLAMA_BIN:-./llama-cli}"

# Parametri di benchmark (modificabili via env)
PROMPT="${PROMPT:-"Ciao, come stai oggi?"}"
TOKENS_TO_GENERATE="${TOKENS_TO_GENERATE:-128}"
CTX_SIZE="${CTX_SIZE:-8192}"
BATCH_SIZE="${BATCH_SIZE:-512}"
THREADS="${THREADS:-4}"
NGL_MAIN="${NGL_MAIN:-99}"
NGL_HELPER="${NGL_HELPER:-99}"

# File di log
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/benchmark_$(date +%Y%m%d_%H%M%S).log"

# Funzioni di supporto
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
log "=== Benchmark EAGLE3 (manuale) ==="
log "Directory lavoro: $SCRIPT_DIR"
log "Assicurarsi che le GPU siano libere prima di proseguire!"
log "Modello principale: $MODEL_PATH_MAIN (GPU $MAIN_GPU)"
log "Modello helper: $MODEL_PATH_HELPER (GPU $HELPER_GPU)"
log "Prompt: \"$PROMPT\""
log "Token da generare: $TOKENS_TO_GENERATE"

# Controlla eseguibile
if [[ ! -x "$LLAMA_BIN" ]]; then
    error "Eseguibile llama.cpp non trovato o non eseguibile: $LLAMA_BIN"
fi
log "Usa eseguibile: $LLAMA_BIN"

# Controlla modelli
check_file "$MODEL_PATH_MAIN"
check_file "$MODEL_PATH_HELPER"

# Crea directory log
mkdir -p "$LOG_DIR"

# === Esegui benchmark ===
log "Avvio misurazione..."

# Cattura VRAM prima (se nvidia-smi è disponibile)
if command -v nvidia-smi &> /dev/null; then
    log "VRAM prima del benchmark:"
    nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv | tee -a "$LOG_FILE"
else
    log "nvidia-smi non trovato, salto misurazione VRAM."
fi

# Registra tempo di inizio
START_TIME=$(date +%s.%N)

# Costruisci comando llama.cpp per EAGLE3
CMD=(
    "$LLAMA_BIN"
    "-m" "$MODEL_PATH_MAIN"
    "--model" "$MODEL_PATH_HELPER"
    "--eagle3"
    "--split-mode" "layer"
    "--main-gpu" "$MAIN_GPU"
    "--helper-gpu" "$HELPER_GPU"
    "--ctx-size" "$CTX_SIZE"
    "--batch-size" "$BATCH_SIZE"
    "--threads" "$THREADS"
    "--ngl" "$NGL_MAIN"
    # Nota: alcune versioni di llama.cpp usano --helper-ngl per il modello helper
    # Se disponibile, lo aggiungiamo; altrimenti lo ignoriamo.
    "--predict" "$TOKENS_TO_GENERATE"
    "--prompt" "$PROMPT"
    "--log-disable"  # disabilita log interno di llama.cpp, noi gestiamo il nostro
)

# Aggiungi eventuale helper-ngl se supportato (proviamo a verificare se il binario lo accetta)
# Per semplicità, lo aggiungiamo comunque; se non supportato, llama.cpp lo ignorerà.
CMD+=("--helper-ngl" "$NGL_HELPER")

log "Esecuzione comando: ${CMD[*]}"
# Esegui e cattura output (sia stdout che stderr) nel log e in una variabile per il parsing
OUTPUT=$("${CMD[@]}" 2>&1 | tee -a "$LOG_FILE")
EXIT_CODE=${PIPESTATUS[0]}

# Registra tempo di fine
END_TIME=$(date +%s.%N)
ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)

log "Benchmark completato in $ELAPSED_TIME secondi."

# Cattura VRAM dopo
if command -v nvidia-smi &> /dev/null; then
    log "VRAM dopo il benchmark:"
    nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv | tee -a "$LOG_FILE"
fi

# Analizza output per estrarre token/s se presente
# Alcune versioni di llama.cpp stampano qualcosa come: "token/s: 45.23"
TOKEN_S=$(echo "$OUTPUT" | grep -oE 'token/s: *[0-9]+.[0-9]+' | grep -oE '[0-9]+.[0-9]+' | tail -1)
if [[ -z "$TOKEN_S" ]]; then
    # Prova un altro pattern comune: "generated 128 tokens in 2.56 s, 49.9 token/s"
    TOKEN_S=$(echo "$OUTPUT" | grep -oE '[0-9]+.[0-9]+ token/s' | grep -oE '[0-9]+.[0-9]+' | tail -1)
fi

# Se non troviamo token/s, calcoliamo approssimativamente
if [[ -z "$TOKEN_S" ]]; then
    TOKEN_S=$(echo "scale=2; $TOKENS_TO_GENERATE / $ELAPSED_TIME" | bc)
    log "Token/s calcolato (approssimativo): $TOKEN_S"
else
    log "Token/s estratto dall'output: $TOKEN_S"
fi

# Latenza media per token (ms)
LATENCY_MS=$(echo "scale=2; ($ELAPSED_TIME * 1000) / $TOKENS_TO_GENERATE" | bc)
log "Latenza media per token: $LATENCY_MS ms"

# Riassunto finale
log "=== RISULTATI BENCHMARK ==="
log "Tempo totale: $ELAPSED_TIME s"
log "Token/s: $TOKEN_S"
log "Latenza/token: $LATENCY_MS ms"
log "Log dettagliato: $LOG_FILE"

# Exit con codice di uscita di llama.cpp
if [[ $EXIT_CODE -ne 0 ]]; then
    error "llama.cpp è terminato con errore (codice $EXIT_CODE, vedi log sopra)"
else
    log "Benchmark completato con successo."
fi