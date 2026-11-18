import { Plugin } from "@opencode/plugin"

/**
 * OpenCode -> Apple Foundation Model compatibility.
 *
 * AFM guided generation does not accept the JSON Schema `pattern` keyword and
 * has a hard 8192-token limit. OpenCode's tool schemas contain `pattern` (in
 * the `subagent` tool) and very long descriptions.
 *
 * This hook rewrites only the outgoing request for the `applefm` provider:
 * it does not change configuration, transcript history, or other providers.
 */

/** Remove the `pattern` keyword without touching properties named "pattern". */
function cleanSchema(node: any, isPropertyMap = false): any {
  if (Array.isArray(node)) return node.map((item) => cleanSchema(item))
  if (!node || typeof node !== "object") return node

  const out: any = {}
  for (const [key, value] of Object.entries(node)) {
    // Inside `properties`, keys are property names, not keywords.
    if (!isPropertyMap && key === "pattern") continue
    out[key] =
      key === "properties" || key === "$defs" || key === "definitions"
        ? cleanSchema(value, true)
        : cleanSchema(value)
  }
  return out
}

/** Keep only the first sentence: tools stay described without filling the context. */
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
