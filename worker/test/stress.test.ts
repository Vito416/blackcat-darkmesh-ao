import { describe, it, expect } from 'vitest'
import app from '../src/index'

describe('stress smoke', () => {
  it('handles concurrent inbox puts', { timeout: 10000 }, async () => {
    const reqs = Array.from({ length: 50 }).map((_, i) =>
      app.request('/inbox', {
        method: 'POST',
        body: JSON.stringify({ nonce: `n${i}`, subject: 'stress', payload: 'x' }),
        headers: { 'content-type': 'application/json', Authorization: 'Bearer test-token' },
      }),
    )
    const res = await Promise.all(reqs)
    res.forEach((r) => expect(r.status).toBe(200))
  })
})
