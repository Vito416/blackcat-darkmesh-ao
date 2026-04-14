import { beforeEach, describe, expect, it, vi } from 'vitest'

const aoClient = {
  message: vi.fn(),
  result: vi.fn(),
}

const connect = vi.fn(() => aoClient)
const createDataItemSigner = vi.fn(() => async () => ({ signature: new Uint8Array(64), address: 'addr-test' }))

vi.mock('@permaweb/aoconnect', () => ({
  default: {
    connect,
    createDataItemSigner,
  },
  connect,
  createDataItemSigner,
}))

import mod from '../src/index'

const baseEnv = {
  TEST_IN_MEMORY_KV: 1,
  AO_HB_URL: 'https://push.forward.computer',
  AO_HB_SCHEDULER: 'n_XZJhUnmldNFo4dhajoPZWhBXuJk-OcQr5JQ49c4Zo',
  AO_REGISTRY_PROCESS_ID: 'REGISTRY_PID_1',
  AO_WALLET_JSON: '{}',
}

async function call(
  body: Record<string, unknown>,
  envOverrides: Record<string, unknown> = {},
  headers: Record<string, string> = {},
) {
  const req = new Request('http://localhost/api/public/site-by-host', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...headers,
    },
    body: JSON.stringify(body),
  })
  return mod.fetch(req, { ...baseEnv, ...envOverrides } as any, {} as any)
}

describe('/api/public/site-by-host', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    aoClient.message.mockReset()
    aoClient.result.mockReset()
  })

  it('returns normalized site metadata on registry hit', async () => {
    aoClient.message.mockResolvedValueOnce('msg-1')
    aoClient.result.mockResolvedValueOnce({
      raw: {
        Output: JSON.stringify({
          status: 'OK',
          data: { siteId: 'site-alpha', activeVersion: 'v1' },
        }),
      },
    })

    const res = await call({ host: 'Shop.EXAMPLE.com', requestId: 'req-site-host-1' }, {}, { 'x-trace-id': 'trace-id-1234' })
    expect(res.status).toBe(200)

    const json = await res.json()
    expect(json).toEqual({
      status: 'OK',
      data: { siteId: 'site-alpha', activeVersion: 'v1' },
      source: 'registry',
    })

    expect(aoClient.message).toHaveBeenCalledTimes(1)
    const payload = aoClient.message.mock.calls[0][0]
    expect(payload.process).toBe('REGISTRY_PID_1')
    expect(payload.data).toBe(
      JSON.stringify({
        Action: 'GetSiteByHost',
        'Request-Id': 'req-site-host-1',
        Host: 'shop.example.com',
      }),
    )
    expect(payload.tags).toEqual(expect.arrayContaining([{ name: 'Action', value: 'GetSiteByHost' }]))
    expect(payload.tags).toEqual(expect.arrayContaining([{ name: 'Host', value: 'shop.example.com' }]))
  })

  it('maps NOT_FOUND to 404', async () => {
    aoClient.message.mockResolvedValueOnce('msg-2')
    aoClient.result.mockResolvedValueOnce({
      raw: {
        Output: JSON.stringify({
          status: 'ERROR',
          code: 'NOT_FOUND',
          message: 'Domain not bound',
        }),
      },
    })

    const res = await call({ host: 'missing.example.com' })
    expect(res.status).toBe(404)
    const json = await res.json()
    expect(json).toMatchObject({ status: 'ERROR', code: 'NOT_FOUND' })
  })

  it('maps shell output without status envelope to 502', async () => {
    aoClient.message.mockResolvedValueOnce('msg-shell')
    aoClient.result.mockResolvedValueOnce({
      raw: {
        Output: {
          'ao-types': 'print=\"atom\"',
          data: 'New Message From Zqk... Action = GetSiteByHost',
          prompt: 'blackcat-ao-registry@aos-2.0.4>',
        },
      },
    })

    const res = await call({ host: 'shop.example.com' })
    expect(res.status).toBe(502)
    const json = await res.json()
    expect(json).toMatchObject({
      status: 'ERROR',
      code: 'INVALID_UPSTREAM_RESPONSE',
      message: 'registry_shell_output_without_envelope',
    })
  })

  it('rejects invalid input with 400', async () => {
    const res = await call({ host: 'https://bad.example.com' })
    expect(res.status).toBe(400)
    const text = await res.text()
    expect(text).toContain('invalid_host')
  })

  it('maps upstream transport failure to 502', async () => {
    aoClient.message.mockRejectedValueOnce(new Error('upstream_down'))

    const res = await call({ host: 'shop.example.com' })
    expect(res.status).toBe(502)
    const json = await res.json()
    expect(json).toMatchObject({ status: 'ERROR', code: 'UPSTREAM_FAILURE' })
    expect(String(json.message)).toContain('upstream_down')
  })
})
