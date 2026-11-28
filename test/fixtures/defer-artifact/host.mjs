// Stand-in plugin host for a mod's hooks modules: node host.mjs <mod dir> <JSON list of tool.describe cases>
// Loads the modules hooks.json names, collects what register(on) hooks, then answers each case the way a middleware
// chain would: matching hooks wrap next(), and a hook that throws is handed to its .catch handler.
// A case is {tool, description, extra fields..., "failFirst": true to make the first next() call throw}.
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const [mod, casesJson] = process.argv.slice(2)
const manifest = JSON.parse(readFileSync(join(mod, 'hooks', 'hooks.json'), 'utf8'))
const hooks = []
const on = (event, matcher, handler) => {
  const hook = { event, matcher, handler, onError: null }
  hooks.push(hook)
  return { catch(fn) { hook.onError = fn; return this } }
}
for (const file of manifest.modules) {
  // A data: URL loads the file as an ES module on any node version, with no package.json beside it.
  const source = readFileSync(join(mod, 'hooks', file), 'utf8')
  const loaded = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'))
  loaded.register(on)
}

const results = []
for (const { failFirst, ...event } of JSON.parse(casesJson)) {
  let calls = 0
  const base = async (e) => {
    calls += 1
    if (failFirst && calls === 1) throw new Error('downstream failed')
    return { description: e.description, inputSchema: { type: 'object' } }
  }
  const matching = hooks.filter((h) => h.event === 'tool.describe' && Object.entries(h.matcher).every(([k, v]) => event[k] === v))
  const chain = matching.reduceRight((next, h) => async (e) => {
    try {
      return await h.handler({}, e, next)
    } catch (error) {
      if (!h.onError) throw error
      return h.onError({}, e, next)
    }
  }, base)
  results.push(await chain(event))
}
console.log(JSON.stringify({ registered: hooks.map((h) => [h.event, h.matcher]), results }))
