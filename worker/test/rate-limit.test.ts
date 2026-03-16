import { describe, it, expect, beforeAll } from 'vitest'
import { unstable_dev } from 'wrangler'

let worker: any

beforeAll(async () => {
  worker = await unstable_dev('src/index.ts', {
    experimental: { disableExperimentalWarning: true },
    kvNamespaces: ['INBOX_KV'],
    kvPersist: false,
    vars: {
      INBOX_TTL_DEFAULT: '60',
      INBOX_TTL_MAX: '300',
      FORGET_TOKEN: 'test-token',
      RATE_LIMIT_MAX: '2',
      RATE_LIMIT_WINDOW: '60',
      REPLAY_TTL: '600',
      SUBJECT_MAX_ENVELOPES: '5',
      PAYLOAD_MAX_BYTES: '10240',
      INBOX_HMAC_SECRET: '',
      TEST_IN_MEMORY_KV: '1',
      MINIFLARE_KV_PERSIST: 'false',
    },
  })
})

afterAll(async () => {
  await worker?.stop()
})

describe('Rate limit', () => {
  it('blocks after limit', async () => {
    const common = { subject: 'rlsubj', payload: 'cipher' }
    await worker.fetch('http://localhost/inbox', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...common, nonce: 'n1' }) })
    await worker.fetch('http://localhost/inbox', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...common, nonce: 'n2' }) })
    const res = await worker.fetch('http://localhost/inbox', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...common, nonce: 'n3' }) })
    expect(res.status).toBe(429)
  })
})
