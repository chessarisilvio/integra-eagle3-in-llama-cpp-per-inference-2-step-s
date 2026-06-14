# Integra EAGLE3 in llama.cpp per inference 2-step su P40+3050

Questo progetto integra la tecnica EAGLE3 (speculative decoding) in llama.cpp per eseguire inference distribuita su due GPU:
- Tesla P40 (GPU 1) per il modello principale
- NVIDIA RTX 3050 (GPU 0) per il modello helper

## Descrizione
Il progetto permette di eseguire modelli LLM GGUF suddivisi tra due GPU utilizzando la tecnica EAGLE3 di llama.cpp, migliorando la velocità di generazione token tramite speculative decoding.

## Architettura
- `run-eagle3.sh`: script per avviare l'inference 2-step con EAGLE3
- `benchmark-manuale.sh`: script di benchmark manuale per misurare tok/s, latenza e VRAM
- `config/settings.json`: configurazione delle GPU e dei percorsi dei modelli
- `logs/`: directory per i log di esecuzione (creata automaticamente)

## Installazione
1. Compilare llama.cpp con supporto per EAGLE3 (opzioni `--eagle3`, `--split-mode`, `--main-gpu`, `--helper-gpu`).
2. Disporre di due GPU: una Tesla P40 e una RTX 3050 (o altre GPU compatibili).
3. Ottenere i modelli GGUF suddivisi in modello principale e modello helper.
4. Copiare i file del progetto in una directory di lavoro.
5. (Facoltativo) creare un virtual environment o assicurarsi di avere le dipendenze di base (bash, nvidia-smi opzionale).

## Uso
- Modificare le variabili d'ambiente o editare `config/settings.json` per impostare:
  - `MODEL_PATH_MAIN`: percorso del modello principale (default: `./models/main_model.gguf`)
  - `MODEL_PATH_HELPER`: percorso del modello helper (default: `./models/helper_model.gguf`)
  - `MAIN_GPU`: indice della GPU per il modello principale (default: 1)
  - `HELPER_GPU`: indice della GPU per il modello helper (default: 0)
- Avviare lo script principale:
  ```bash
  ./run-eagle3.sh [opzioni llama.cpp]
  ```
  Le opzioni aggiuntive vengono passate direttamente a llama.cpp.
- Per misurare le prestazioni, utilizzare lo script di benchmark:
  ```bash
  ./benchmark-manuale.sh
  ```
  (Nota: assicurarsi che le GPU siano libere da altri processi prima dell'esecuzione.)

## Esempi
```bash
export MODEL_PATH_MAIN=/path/to/main_model.gguf
export MODEL_PATH_HELPER=/path/to/helper_model.gguf
export MAIN_GPU=1
export HELPER_GPU=0
./run-eagle3.sh -p "Ciao mondo" -n 128
```

## Stato
✅ COMPLETATO — 2026-06-12

## Note sulla privacy
Questo progetto rispetta la privacy: non utilizza path assoluti hardcoded né dati personali.
Tutte le configurazioni sono effettuabili tramite variabili d'ambiente o file di configurazione relativi.

## Licenza
Questo progetto è destinato a essere pubblicato pubblicamente. Assicurarsi di non includere informazioni sensibili prima del commit.