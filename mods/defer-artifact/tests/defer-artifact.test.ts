import { expect, test } from 'claude-code/testing'

const core = { plugin: 'engine', tier: 'core' } as const

test('Artifact is put behind ToolSearch', async ($, on) => {
  // Claude Code's own answer: the description, no deferral
  on('tool.describe', ($, e) => ({ description: e.description }))
  const out = await $.tool.describe({ tool: 'Artifact', description: 'Renders an HTML file as an Artifact', provider: core })
  expect(out.isDeferred).toBe(true)
  expect(out.description).toBe('Renders an HTML file as an Artifact')
})

test('Bash is left as it is', async ($, on) => {
  on('tool.describe', ($, e) => ({ description: e.description }))
  const out = await $.tool.describe({ tool: 'Bash', description: 'Runs a shell command', provider: core })
  expect(out.isDeferred).toBeUndefined()
  expect(out).toEqual({ description: 'Runs a shell command' })
})
