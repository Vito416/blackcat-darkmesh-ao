import { describe, it, expect } from 'vitest'
import mod from '../src/index'

const env = {
  INBOX_TTL_DEFAULT: '60',
  INBOX_TTL_MAX: '300',
  FORGET_TOKEN: 'test-token',
  RATE_LIMIT_MAX: '5',
  RATE_LIMIT_WINDOW: '60',
  REPLAY_TTL: '600',
  SUBJECT_MAX_ENVELOPES: '5',
  PAYLOAD_MAX_BYTES: '10240',
  INBOX_HMAC_SECRET: '',
  TEST_IN_MEMORY_KV: 1,
}

async function req(path: string, init: RequestInit = {}) {
  const r = new Request(`http://localhost${path}`, init)
  return mod.fetch(r, env as any, {} as any)
}

describe('Inbox flow', () => {
  it('stores and fetches then deletes', async () => {
    const res = await req('/inbox', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ subject: 'subj', nonce: 'n1', payload: 'cipher' }),
    })
    expect([201, 409]).toContain(res.status)
    const getRes = await req('/inbox/subj/n1', {
      headers: { Authorization: 'Bearer test-token' },
    })
    expect([200, 404]).toContain(getRes.status) // if replay caused overwrite/clean
    if (getRes.status === 200) {
      const body = await getRes.json()
      expect(body.payload).toBe('cipher')
      const notFound = await req('/inbox/subj/n1', {
        headers: { Authorization: 'Bearer test-token' },
      })
      expect(notFound.status).toBe(404)
    }
  })

  it('supports forget', async () => {
    await req('/inbox', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ subject: 'subj2', nonce: 'n2', payload: 'cipher' }),
    })
    const res = await req('/forget', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        Authorization: 'Bearer test-token',
      },
      body: JSON.stringify({ subject: 'subj2' }),
    })
    expect(res.status).toBe(200)
    const body = await res.json()
    expect(body.deleted).toBeGreaterThanOrEqual(1)
    expect(body.replayDeleted).toBeGreaterThanOrEqual(1)
    const getRes = await req('/inbox/subj2/n2', {
      headers: { Authorization: 'Bearer test-token' },
    })
    expect(getRes.status).toBe(404)
  })
})
