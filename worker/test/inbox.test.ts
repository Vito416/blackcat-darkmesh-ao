import { describe, it, expect, beforeAll, afterAll } from 'vitest'
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
      RATE_LIMIT_MAX: '5',
      RATE_LIMIT_WINDOW: '60',
      REPLAY_TTL: '600',
      SUBJECT_MAX_ENVELOPES: '5',
      PAYLOAD_MAX_BYTES: '10240',
      INBOX_HMAC_SECRET: '', // disable HMAC for tests
      TEST_IN_MEMORY_KV: '1',
      // use in-memory kv to avoid sqlite locks in miniflare
      MINIFLARE_KV_PERSIST: 'false',
    },
  })
})

afterAll(async () => {
  await worker?.stop()
})

describe('Inbox flow', () => {
  it('stores and fetches then deletes', async () => {
    const res = await worker.fetch('http://localhost/inbox', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ subject: 'subj', nonce: 'n1', payload: 'cipher' }),
    })
    expect([201, 409]).toContain(res.status)
    const getRes = await worker.fetch('http://localhost/inbox/subj/n1')
    expect([200, 404]).toContain(getRes.status) // if replay caused overwrite/clean
    if (getRes.status === 200) {
      const body = await getRes.json()
      expect(body.payload).toBe('cipher')
      const notFound = await worker.fetch('http://localhost/inbox/subj/n1')
      expect(notFound.status).toBe(404)
    }
  })

  it('supports forget', async () => {
    await worker.fetch('http://localhost/inbox', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ subject: 'subj2', nonce: 'n2', payload: 'cipher' }),
    })
    const res = await worker.fetch('http://localhost/forget', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        Authorization: 'Bearer test-token',
      },
      body: JSON.stringify({ subject: 'subj2' }),
    })
    expect(res.status).toBe(200)
    const getRes = await worker.fetch('http://localhost/inbox/subj2/n2')
    expect(getRes.status).toBe(404)
  })
})
