# OpenCode + Apple Foundation Model (on-device)

Setup distribuibile per usare il **Foundation Model incluso in macOS 27** dentro [OpenCode](https://opencode.ai/) come provider OpenAI-compatible, con **tool calling funzionante**.

## Stato verificato

Testato il 2026-11-18 su:

| Componente | Versione |
| --- | --- |
| macOS | 27.2.1 (build 26B131), Apple Silicon |
| Modello | `system` = **AFM 3 Core Advanced** (on-device, multimodale) |
| `fm` | `/usr/bin/fm`, licenza accettata |
| OpenCode | v2.3.0 |

Il tool calling di `fm serve` era regressionato sulle build 27.0.x (nessun `tool_calls` emesso). **Su 27.2.1 è ripristinato**: questo repo usa quindi direttamente `fm serve`, senza bridge Python. Se distribuisci su Mac con 27.0.x, usa `./install.sh --no-tools` oppure aggiorna il sistema.

## Come funziona

```
OpenCode  --hook "context"-->  plugin applefm-compat  --HTTP /v1/chat/completions-->  fm serve  --> AFM 3 Core Advanced
                                      |                                                  |
                                      +-- schema tool AFM-safe                            +-- OpenCode esegue i tool
```

- `fm serve` ascolta solo su `127.0.0.1:1976` (modificabile con `FM_PORT`).
- Nessuna API key, nessun account, nessun costo per token, funziona offline dopo il download iniziale del modello.
- Un LaunchAgent mantiene il servizio attivo.
- La configurazione OpenCode usa la sintassi **V2** (`providers` + `package`/`settings`), non il vecchio `provider`/`npm`/`options`.

### Perché un plugin

Gli schemi dei tool inviati da OpenCode non sono compatibili con AFM: contengono la keyword JSON Schema `pattern` (nel tool `subagent`) e descrizioni così lunghe da superare il limite di 8192 token. Il plugin `applefm-compat`, registrato solo per il provider `applefm`, riscrive la richiesta in uscita:

- rimuove la keyword `pattern` senza toccare le proprietà chiamate “pattern” di `glob`/`grep`;
- accorcia le descrizioni dei tool alla prima frase;
- non modifica config, cronologia o altri provider.

Non aggiunge dipendenze npm: OpenCode carica direttamente il file `.ts` dalla directory di configurazione.

### Perché i checkpoint automatici sono disattivati

Con soli 8192 token OpenCode compatta molto presto e produce un riepilogo che viene reiniettato nel contesto. Il modello on-device lo interpreta come “Next Move” e tende a rieseguire lo stesso tool in loop. L’installer imposta quindi `"compaction": {"auto": false}` nella configurazione globale: le risposte diventano immediate e i tool vengono eseguiti una sola volta. Se usi anche provider con contesto ampio e vuoi i checkpoint, reinstalla con `--keep-compaction`. Nota che l’impostazione è globale, non specifica di `applefm`.

## Requisiti

- macOS 27+, Apple Silicon.
- Apple Intelligence attivo e modello scaricato.
- Licenza CLI accettata una volta per macchina: `sudo fm license`.
- `python3`, `curl`, `lsof` (presenti di default con Xcode Command Line Tools).
- OpenCode v2.

## Installazione

```bash
git clone <questo-repo> opencode-apple-fm
cd opencode-apple-fm
chmod +x install.sh uninstall.sh
./install.sh
```

Opzioni:

```bash
FM_PORT=1977 ./install.sh          # porta diversa
./install.sh --no-tools            # disabilita tool calling (macOS 27.0.x)
./install.sh --keep-compaction     # mantiene i checkpoint automatici di OpenCode
```

Lo script:

1. verifica macOS/Apple Silicon/`fm`/licenza/modello/porta libera (riconosce il proprio `fm serve` in caso di reinstallazione);
2. fa un backup di `~/.config/opencode/opencode.jsonc` e lo aggiorna in modo non distruttivo (provider, agente e `compaction.auto`);
3. rimuove il vecchio provider V1 `fm` se presente;
4. installa il plugin in `~/.config/opencode/plugins/applefm-compat/`;
5. installa `~/Library/LaunchAgents/ai.opencode.applefm.plist` e avvia il servizio;
6. esegue uno smoke test end-to-end con un tool call e il suo risultato.

## Utilizzo

Dentro OpenCode:

```text
/models        -> applefm/system
/agent         -> applefm (opzionale)
```

Oppure per una singola esecuzione:

```bash
opencode run --model applefm/system "Spiegami cos'è un closure in Swift in due righe"
```

Per test che usano i tool in modalità non interattiva aggiungi `--auto`, che approva i permessi non esplicitamente negati:

```bash
opencode run --auto --model applefm/system \
  "Usa il tool glob con pattern 'README.md' per verificare che il file esista"
```

Per usarlo come default solo in un progetto, crea `opencode.json` nella root del progetto:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "applefm/system"
}
```

La configurazione viene ricaricata automaticamente da OpenCode.

## Verifica manuale

```bash
curl -s http://127.0.0.1:1976/health
curl -s http://127.0.0.1:1976/v1/models
python3 scripts/smoke-test.py 1976

# Test through OpenCode (più lento, include un tool call)
chmod +x scripts/smoke-test-opencode.sh
./scripts/smoke-test-opencode.sh
```

## Limiti noti

- **Contesto 8.192 token**, di cui ~8.132 utilizzabili per prompt + risposta. Non è un sostituto di un modello di coding da 200K.
- La compattazione automatica è disattivata: sessioni molto lunghe prima o poi supereranno i 8K. In quel caso usa `/compact` manualmente o riavvia la sessione.
- Le immagini funzionano solo come `data:image/...;base64,...` inline; `fm serve` non scarica URL remoti.
- `max_tokens` viene accettato ma ignorato dal server; `stop`, `n` e `reasoning_effort` restituiscono 400.
- `pcc` compare in `/v1/models` ma non è utilizzabile da processi non-Terminal; il provider configurato espone solo `system`.
- `fm serve` **non fa autenticazione**: non esporlo mai fuori da localhost (non usare `--host 0.0.0.0`).
- I log di `fm serve` sono TTY-gated e possono risultare vuoti se rediretti.

## Troubleshooting

| Sintomo | Cosa controllare |
| --- | --- |
| `fm` dice “YOU HAVE NOT AGREED...” | `sudo fm license` |
| `✗ system` in `fm models` | Attiva Apple Intelligence e lascia scaricare il modello |
| `Model unavailable: applefm/system` | Verifica `/models`; la porta deve essere libera e `/health` rispondere |
| Nessun `tool_calls` | Build 27.0.x: aggiorna a 27.2+ o reinstalla con `--no-tools` |
| `A generation guide with an unsupported pattern was used` | Il plugin non è caricato: controlla `~/.config/opencode/plugins/applefm-compat/index.ts` e riavvia OpenCode |
| `Provided N tokens, but the maximum allowed is 8192` | Il plugin non è caricato o il prompt è troppo lungo; accorcia il contesto |
| `opencode run` resta appeso su un tool | Aggiungi `--auto` per approvare i permessi; se il modello ripete sempre lo stesso tool, controlla che `compaction.auto` sia `false` |
| Porta occupata | `lsof -nP -iTCP:1976 -sTCP:LISTEN`; usa `FM_PORT` |
| Servizio non parte | `launchctl print gui/$(id -u)/ai.opencode.applefm`; controlla `~/.local/share/opencode-apple-fm/` |

## Disinstallazione

```bash
./uninstall.sh
```

Rimuove il LaunchAgent, il plist, il plugin e le chiavi `providers.applefm` / `agents.applefm` dalla configurazione globale, preservando le altre impostazioni.

## File

```text
install.sh                                  # installatore idempotente
uninstall.sh                                # rimozione
plugins/applefm-compat/index.ts             # plugin OpenCode (compatibilità AFM)
scripts/smoke-test.py                       # test /health, /models, tool round-trip
scripts/smoke-test-opencode.sh              # test end-to-end through OpenCode
config/opencode.snippet.jsonc               # configurazione OpenCode V2 di riferimento
launchd/ai.opencode.applefm.plist.template  # LaunchAgent
```

## Riferimenti

- [Foundation Models framework](https://developer.apple.com/documentation/foundationmodels)
- [Foundation Models SDK for Python](https://apple.github.io/python-apple-fm-sdk/) (non necessario qui)
- [OpenCode providers](https://opencode.ai/docs/providers/)
- [OpenCode models / local](https://opencode.ai/docs/models/#local)
