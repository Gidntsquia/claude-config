// defer-artifact: send the built-in Artifact tool as a one-line deferred entry instead of its full schema.
// Claude loads the full definition through ToolSearch when it wants to read or publish an artifact.
// Needs Claude Code 2.1.293 or later. Touches no other tool.
export function register(on) {
  on('tool.describe', { tool: 'Artifact' }, async ($, e, next) => {
    const described = await next(e)
    return { ...described, isDeferred: true }
  }).catch(($, e, next) => next(e))
}
