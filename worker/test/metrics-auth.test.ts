import { describe, it, expect, beforeAll } from 'vitest'
import { unstable_dev } from 'wrangler'

let worker: any

beforeAll(async () => {
  worker = await unstable_dev('src/index.ts', {
    experimental: { disableExperimentalWarning: true },
    kvNamespaces: ['INBOX_KV'],
    kvPersist: false,
    vars: {
      METRICS_BASIC_USER: 'u',
      METRICS_BASIC_PASS: 'p',
      METRICS_BEARER_TOKEN: 't1',
      TEST_IN_MEMORY_KV: '1',
    },
  })
})

afterAll(async () => {
  await worker?.stop()
})

describe('/metrics auth (worker)', () => {
  it('rejects when missing', async () => {
    const res = await worker.fetch('http://localhost/metrics')
    expect(res.status).toBe(401)
  })

  it('accepts bearer', async () => {
    const res = await worker.fetch('http://localhost/metrics', { headers: { authorization: 'Bearer t1' } })
    expect(res.status).toBe(200)
  })

  it('accepts basic', async () => {
    const token = Buffer.from('u:p').toString('base64')
    const res = await worker.fetch('http://localhost/metrics', { headers: { authorization: `Basic ${token}` } })
    expect(res.status).toBe(200)
  })
})
