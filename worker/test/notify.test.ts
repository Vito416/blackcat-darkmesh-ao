import { describe, it, expect, beforeEach, vi } from 'vitest'
import mod from '../src/index'

const baseEnv = {
  FORGET_TOKEN: 't',
  TEST_IN_MEMORY_KV: 1,
  NOTIFY_DEDUPE_TTL: '600',
  NOTIFY_RETRY_MAX: '1',
  NOTIFY_RETRY_BACKOFF_MS: '0',
  NOTIFY_BREAKER_THRESHOLD: '1',
  NOTIFY_BREAKER_COOLDOWN: '300',
}

async function req(body: any, envOverrides: Record<string, any> = {}) {
  const env = { ...baseEnv, ...envOverrides } as any
  const r = new Request('http://localhost/notify', {
    method: 'POST',
    headers: { Authorization: 'Bearer t', 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
  return mod.fetch(r, env, {} as any)
}

describe('/notify dedupe and breaker', () => {
  beforeEach(() => {
    vi.restoreAllMocks()
  })

  it('dedupes repeated webhook payload', async () => {
    const fetchSpy = vi.spyOn(global, 'fetch' as any).mockResolvedValue(new Response('', { status: 200 }))
    const payload = { webhookUrl: 'https://example.com/hook', data: { x: 1 } }
    const res1 = await req(payload)
    expect(res1.status).toBe(200)
    const res2 = await req(payload)
    expect(res2.status).toBe(200)
    const body2 = await res2.json()
    expect(body2.deduped).toBe(true)
    expect(fetchSpy).toHaveBeenCalledTimes(1)
  })

  it('opens breaker after failure and blocks subsequent calls', async () => {
    const fetchSpy = vi
      .spyOn(global, 'fetch' as any)
      .mockResolvedValue(new Response('', { status: 500 }))
    const payload = { webhookUrl: 'https://example.com/fail', data: { y: 2 } }
    const res1 = await req(payload, { NOTIFY_BREAKER_THRESHOLD: '1', NOTIFY_RETRY_MAX: '1', NOTIFY_RETRY_BACKOFF_MS: '0' })
    expect(res1.status).toBe(502)
    const res2 = await req(payload, { NOTIFY_BREAKER_THRESHOLD: '1', NOTIFY_RETRY_MAX: '1', NOTIFY_RETRY_BACKOFF_MS: '0' })
    expect(res2.status).toBe(429)
    const res3 = await req(payload, { NOTIFY_BREAKER_THRESHOLD: '1', NOTIFY_RETRY_MAX: '1', NOTIFY_BREAKER_COOLDOWN: '600' })
    expect(res3.status).toBe(429)
    expect(fetchSpy).toHaveBeenCalledTimes(1)
  })
})
