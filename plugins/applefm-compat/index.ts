import { Plugin } from "@opencode/plugin"

/**
 * Compatibilità OpenCode -> Apple Foundation Model.
 *
 * AFM guided generation non accetta la keyword JSON Schema `pattern` e ha un
 * limite duro di 8192 token. Lo schema dei tool di OpenCode contiene invece
 * `pattern` (nel tool `subagent`) e descrizioni molto lunghe.
 *
 * Questo hook riscrive solo la richiesta in uscita per il provider `applefm`:
 * non modifica la configurazione, la cronologia o gli altri provider.
 */

/** Rimuove la keyword `pattern`, senza toccare le proprietà chiamate "pattern". */
function cleanSchema(node: any, isPropertyMap = false): any {
  if (Array.isArray(node)) return node.map((item) => cleanSchema(item))
  if (!node || typeof node !== "object") return node

  const out: any = {}
  for (const [key, value] of Object.entries(node)) {
    // Dentro `properties` le chiavi sono nomi di proprietà, non keyword.
    if (!isPropertyMap && key === "pattern") continue
    out[key] =
      key === "properties" || key === "$defs" || key === "definitions"
        ? cleanSchema(value, true)
        : cleanSchema(value)
  }
  return out
}

/** Tiene solo la prima frase: i tool restano descritti, senza saturare il contesto. */
function shorten(description: unknown): unknown {
  if (typeof description !== "string") return description
  const firstSentence = description.match(/^.+?[.!?](?=\s|$)/s)?.[0]
  const candidate = (firstSentence ?? description.split(/\n/, 1)[0]).trim()
  if (candidate.length <= 180) return candidate
  return candidate.slice(0, 177).replace(/\s+\S*$/, "") + "..."
}

export default Plugin.define({
  id: "applefm-compat",
  setup(ctx) {
    ctx.session.hook(
      "context",
      (event) => {
        for (const tool of Object.values(event.tools ?? {})) {
          if (!tool || typeof tool !== "object") continue
          const t = tool as any
          if ("input" in t) t.input = cleanSchema(t.input)
          if ("description" in t) t.description = shorten(t.description)
        }
      },
      { providerID: "applefm" },
    )
  },
})
