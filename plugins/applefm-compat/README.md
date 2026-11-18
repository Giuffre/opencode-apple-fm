# opencode-applefm-compat

Plugin per **OpenCode V2** che rende gli schemi dei tool compatibili con il Foundation Model on-device di Apple (`fm serve`).

## Perché serve

OpenCode invia al modello gli schemi JSON Schema dei propri tool. AFM non supporta la keyword `pattern` (presente nel tool `subagent`) e ha un limite duro di 8192 token, che le descrizioni lunghe dei tool superano. Senza questo plugin le richieste con tool falliscono con:

- `A generation guide with an unsupported pattern was used.`
- `Provided N tokens, but the maximum allowed is 8192.`

## Cosa fa

Registra un hook `context` solo per il provider `applefm`:

- rimuove la keyword JSON Schema `pattern` senza toccare le proprietà chiamate “pattern” di `glob`/`grep`;
- accorcia le descrizioni dei tool alla prima frase;
- non modifica configurazione, cronologia o altri provider.

## Installazione

Il plugin presume che esista già un provider OpenCode V2 chiamato `applefm` che punta a `http://127.0.0.1:<porta>/v1`.

Per il setup completo — licenza `fm`, LaunchAgent, provider, plugin e test — usa l’installer del repository:

```bash
git clone https://github.com/Giuffre/opencode-apple-fm.git
cd opencode-apple-fm
./install.sh
```

Se il provider è già configurato e vuoi solo il plugin:

```bash
opencode plugin add opencode-applefm-compat
```

Oppure copia `index.ts` in `~/.config/opencode/plugins/applefm-compat/`: OpenCode lo carica automaticamente.

## Compatibilità

Verificato con OpenCode `2.3.0`, macOS `27.2.1` (Apple Silicon), modello `system` = AFM 3 Core Advanced. L’API plugin V2 è beta: controlla le versioni prima di aggiornare OpenCode.

## Licenza

MIT — vedi `LICENSE` nel repository.
