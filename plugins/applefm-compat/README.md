# opencode-applefm-compat

A plugin for **OpenCode V2** that makes tool schemas compatible with Apple's on-device Foundation Model (`fm serve`).

## Why it exists

OpenCode sends the JSON Schema of its tools to the model. AFM does not support the `pattern` keyword (used by the `subagent` tool) and has a hard 8192-token limit that long tool descriptions can exceed. Without this plugin, requests containing tools fail with:

- `A generation guide with an unsupported pattern was used.`
- `Provided N tokens, but the maximum allowed is 8192.`

## What it does

Registers a `context` hook only for the `applefm` provider:

- removes the JSON Schema `pattern` keyword without touching properties actually named “pattern” in `glob`/`grep`;
- shortens tool descriptions to their first sentence;
- does not modify configuration, transcript history, or other providers.

## Installation

The plugin assumes an OpenCode V2 provider named `applefm` already points to `http://127.0.0.1:<port>/v1`.

For the complete setup — `fm` license, LaunchAgent, provider, plugin, and tests — use the repository installer:

```bash
git clone https://github.com/Giuffre/opencode-apple-fm.git
cd opencode-apple-fm
./install.sh
```

If the provider is already configured and you only want the plugin:

```bash
opencode plugin add opencode-applefm-compat
```

Or copy `index.ts` into `~/.config/opencode/plugins/applefm-compat/`: OpenCode loads it automatically.

## Compatibility

Verified with OpenCode `2.3.0`, macOS `27.2.1` (Apple Silicon), model `system` = AFM 3 Core Advanced. The V2 plugin API is beta: check versions before upgrading OpenCode.

## License

MIT — see `LICENSE` in the repository.
