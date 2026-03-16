import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { unstable_dev } from 'wrangler'

let worker: any

async function fetchWithTimeout(input: any, init: any = {}, ms = 5000) {
  const ac = new AbortController()
  const t = setTimeout(() => ac.abort('timeout'), ms)
  try {
    return await worker.fetch(input, { ...init, signal: ac.signal })
  } finally {
    clearTimeout(t)
  }
}

beforeAll(async () => {
  worker = await unstable_dev('src/index.ts', {
    experimental: { disableExperimentalWarning: true },
    kvNamespaces: ['INBOX_KV'],
    kvPersist: false,
    vars: {
      INBOX_TTL_DEFAULT: '30',
      INBOX_TTL_MAX: '30',
      TEST_IN_MEMORY_KV: '1',
    },
  })
})

afterAll(async () => {
  await worker?.stop()
})

describe('janitor expires items', () => {
  it('deletes expired envelopes on scheduled', async () => {
    // store with short ttl
    await fetchWithTimeout('http://localhost/inbox', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ subject: 'jan', nonce: 'x1', payload: 'p', ttlSeconds: 1 }),
    })
    // advance time by 2s
    await new Promise((r) => setTimeout(r, 1200))
    // call scheduled with stub KV that points to same in-memory store via KVNamespace interface
    const map = new Map<string, string>()
    const kv = {
      async get(key: string) { return map.get(key) || null },
      async put(key: string, value: string) { map.set(key, value) },
      async delete(key: string) { map.delete(key) },
      async list(params?: { prefix?: string }) {
        const prefix = params?.prefix || ''
        const keys = []
        for (const k of map.keys()) { if (k.startsWith(prefix)) keys.push({ name: k }) }
        return { keys }
      },
    }
    // seed same map with the stored item to simulate shared KV
    map.set('jan:x1', JSON.stringify({ payload: 'p', exp: Math.floor(Date.now() / 1000) - 1 }))
    const mod = await import('../src/index')
    const env: any = { TEST_IN_MEMORY_KV: 0, INBOX_KV: kv }
    const ctx: any = { waitUntil: (p: Promise<any>) => p }
    if (mod.default && typeof mod.default.scheduled === 'function') {
      await mod.default.scheduled({ cron: '' } as any, env, ctx)
    }
    const res = await fetchWithTimeout('http://localhost/inbox/jan/x1')
    expect(res.status).toBe(404)
  })
})
