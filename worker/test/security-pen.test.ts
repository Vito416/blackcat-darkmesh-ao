import { describe, it, expect, vi } from 'vitest'
import crypto from 'crypto'
import mod from '../src/index'

const baseEnv = {
  TEST_IN_MEMORY_KV: 1,
  INBOX_TTL_DEFAULT: '60',
  INBOX_TTL_MAX: '300',
  SUBJECT_MAX_ENVELOPES: '5',
  PAYLOAD_MAX_BYTES: '20480',
  RATE_LIMIT_MAX: '5',
  RATE_LIMIT_WINDOW: '60',
  REPLAY_TTL: '600',
  NOTIFY_RETRY_MAX: '1',
  NOTIFY_RETRY_BACKOFF_MS: '0',
  NOTIFY_BREAKER_THRESHOLD: '2',
  FORGET_TOKEN: 't',
}

function hmacHex(secret: string, body: string) {
  return crypto.createHmac('sha256', secret).update(body).digest('hex')
}

async function call(path: string, init: RequestInit, envOverrides: Record<string, any>) {
  const env = { ...baseEnv, ...envOverrides } as any
  const req = new Request(`http://localhost${path}`, init)
  return mod.fetch(req, env, {} as any)
}

describe('Inbox HMAC hardening', () => {
  const secret = 'inbox-secret'
  const body = JSON.stringify({ subject: 's1', nonce: 'n1', payload: 'cipher' })

  it('rejects missing signature when HMAC required', async () => {
    const res = await call('/inbox', { method: 'POST', body, headers: { 'content-type': 'application/json' } }, { INBOX_HMAC_SECRET: secret })
    expect(res.status).toBe(401)
  })

  it('rejects invalid signature', async () => {
    const res = await call(
      '/inbox',
      { method: 'POST', body, headers: { 'content-type': 'application/json', 'x-signature': 'deadbeef' } },
      { INBOX_HMAC_SECRET: secret }
    )
    expect(res.status).toBe(401)
  })

  it('accepts valid signature', async () => {
    const sig = hmacHex(secret, body)
    const res = await call(
      '/inbox',
      { method: 'POST', body, headers: { 'content-type': 'application/json', 'x-signature': sig } },
      { INBOX_HMAC_SECRET: secret }
    )
    expect(res.status).toBe(201)
  })
})

describe('Notify HMAC hardening', () => {
  const secret = 'notify-secret'
  const body = JSON.stringify({ webhookUrl: 'https://example.com/hook', data: { x: 1 } })

  it('rejects missing signature when NOTIFY_HMAC_SECRET set', async () => {
    const res = await call(
      '/notify',
      { method: 'POST', body, headers: { 'content-type': 'application/json', Authorization: 'Bearer t' } },
      { NOTIFY_HMAC_SECRET: secret }
    )
    expect(res.status).toBe(401)
  })

  it('accepts valid signature', async () => {
    const sig = hmacHex(secret, body)
    const fetchSpy = vi.spyOn(global, 'fetch' as any).mockResolvedValue(new Response('', { status: 200 }))
    const res = await call(
      '/notify',
      {
        method: 'POST',
        body,
        headers: { 'content-type': 'application/json', Authorization: 'Bearer t', 'x-signature': sig },
      },
      { NOTIFY_HMAC_SECRET: secret }
    )
    expect([200, 202]).toContain(res.status)
    fetchSpy.mockRestore()
  })
})
