import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { createServer } from 'node:net'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const SERVER_SCRIPT = path.join(PROJECT_ROOT, 'scripts/http/public_api_server.mjs')
const STARTUP_TIMEOUT_MS = 60000

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function getFreePort() {
  return new Promise((resolve, reject) => {
    const probe = createServer()
    probe.once('error', reject)
    probe.listen(0, '127.0.0.1', () => {
      const address = probe.address()
      if (!address || typeof address === 'string') {
        probe.close(() => reject(new Error('free_port_unavailable')))
        return
      }
      probe.close((err) => {
        if (err) {
          reject(err)
          return
        }
        resolve(address.port)
      })
    })
  })
}

async function readJson(res) {
  const raw = await res.text()
  return JSON.parse(raw)
}

async function waitForServer(baseUrl, child, getLogs) {
  const deadline = Date.now() + STARTUP_TIMEOUT_MS
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      const logs = getLogs()
      throw new Error(
        `server_exited_early:${child.exitCode}\nstdout:\n${logs.stdout}\nstderr:\n${logs.stderr}`,
      )
    }
    try {
      const res = await fetch(`${baseUrl}/healthz`)
      if (res.status === 200) return
    } catch {
      // keep retrying until startup timeout
    }
    await delay(50)
  }
  const logs = getLogs()
  throw new Error(`server_start_timeout\nstdout:\n${logs.stdout}\nstderr:\n${logs.stderr}`)
}

async function startServer(envOverrides = {}) {
  const port = await getFreePort()
  let stdout = ''
  let stderr = ''

  const child = spawn(process.execPath, [SERVER_SCRIPT], {
    cwd: PROJECT_ROOT,
    env: {
      ...process.env,
      HOST: '127.0.0.1',
      PORT: String(port),
      AO_SITE_PROCESS_ID: 'SITE_CONTRACT_TEST_PID',
      AO_DISABLE_DRYRUN: '1',
      AO_READ_FALLBACK_TO_SCHEDULER: '0',
      AO_HB_URL: 'http://127.0.0.1:1',
      AO_PUBLIC_API_TOKEN: '',
      ...envOverrides,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  child.stdout.setEncoding('utf8')
  child.stderr.setEncoding('utf8')
  child.stdout.on('data', (chunk) => {
    stdout += chunk
  })
  child.stderr.on('data', (chunk) => {
    stderr += chunk
  })

  const baseUrl = `http://127.0.0.1:${port}`
  try {
    await waitForServer(baseUrl, child, () => ({ stdout, stderr }))
  } catch (error) {
    if (child.exitCode === null) {
      child.kill('SIGKILL')
    }
    throw error
  }

  return {
    baseUrl,
    child,
    getLogs: () => ({ stdout, stderr }),
  }
}

async function stopServer(server) {
  if (!server || !server.child) return
  const { child } = server
  if (child.exitCode !== null) return

  const exited = new Promise((resolve) => {
    child.once('exit', () => resolve(true))
  })

  child.kill('SIGTERM')
  const graceful = await Promise.race([exited, delay(1500).then(() => false)])
  if (!graceful && child.exitCode === null) {
    child.kill('SIGKILL')
    await exited
  }
}

async function postJson(baseUrl, pathName, body, headers = {}) {
  return fetch(`${baseUrl}${pathName}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...headers,
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  })
}

test('public API health + route/method/auth/invalid-body contract', async (t) => {
  const token = 'CONTRACT_TOKEN'
  const authHeaders = { 'x-api-token': token }
  const bearerHeaders = { authorization: `Bearer ${token}` }
  const server = await startServer({ AO_PUBLIC_API_TOKEN: token })
  const { baseUrl } = server

  try {
    await t.test('GET /healthz returns stable smoke payload', async () => {
      const res = await fetch(`${baseUrl}/healthz`)
      const body = await readJson(res)

      assert.equal(res.status, 200)
      assert.equal(body.ok, true)
      assert.equal(body.service, 'ao-public-api')
      assert.equal(body.sitePidConfigured, true)
      assert.equal(typeof body.now, 'string')
      assert.notEqual(Number.isNaN(Date.parse(body.now)), true)
    })

    await t.test('token-protected mode rejects missing auth', async () => {
      const res = await postJson(baseUrl, '/api/public/resolve-route', {})
      const body = await readJson(res)

      assert.equal(res.status, 401)
      assert.equal(body.ok, false)
      assert.equal(body.error, 'unauthorized')
    })

    await t.test('non-public route returns 404', async () => {
      const res = await postJson(baseUrl, '/api/public/not-a-route', {}, authHeaders)
      const body = await readJson(res)

      assert.equal(res.status, 404)
      assert.equal(body.ok, false)
      assert.equal(body.error, 'not_found')
    })

    await t.test('GET is rejected on read endpoints', async () => {
      const routeRes = await fetch(`${baseUrl}/api/public/resolve-route`, {
        method: 'GET',
        headers: bearerHeaders,
      })
      const routeBody = await readJson(routeRes)
      assert.equal(routeRes.status, 405)
      assert.equal(routeBody.error, 'method_not_allowed')

      const pageRes = await fetch(`${baseUrl}/api/public/page`, {
        method: 'GET',
        headers: authHeaders,
      })
      const pageBody = await readJson(pageRes)
      assert.equal(pageRes.status, 405)
      assert.equal(pageBody.error, 'method_not_allowed')
    })

    await t.test('OPTIONS advertises trace header and echoes valid trace ID', async () => {
      const res = await fetch(`${baseUrl}/api/public/page`, {
        method: 'OPTIONS',
        headers: {
          ...authHeaders,
          'x-trace-id': 'trace-contract-001',
        },
      })
      assert.equal(res.status, 204)
      assert.match(String(res.headers.get('access-control-allow-headers') || ''), /\bx-trace-id\b/i)
      assert.equal(res.headers.get('x-trace-id'), 'trace-contract-001')
    })

    await t.test('invalid JSON body is rejected on both endpoints', async () => {
      const routeRes = await postJson(
        baseUrl,
        '/api/public/resolve-route',
        '{"broken":',
        authHeaders,
      )
      const routeBody = await readJson(routeRes)
      assert.equal(routeRes.status, 400)
      assert.equal(routeBody.error, 'invalid_json')

      const pageRes = await postJson(baseUrl, '/api/public/page', '[]', bearerHeaders)
      const pageBody = await readJson(pageRes)
      assert.equal(pageRes.status, 400)
      assert.equal(pageBody.error, 'invalid_json')
    })

    await t.test('trace ID is propagated in error response headers', async () => {
      const res = await postJson(
        baseUrl,
        '/api/public/resolve-route',
        {},
        {
          ...authHeaders,
          'x-trace-id': 'trace-contract-002',
        },
      )
      const body = await readJson(res)
      assert.equal(res.status, 400)
      assert.equal(body.error, 'site_id_required')
      assert.equal(res.headers.get('x-trace-id'), 'trace-contract-002')
    })

    await t.test('invalid request body fields return endpoint-specific errors', async () => {
      const routeRes = await postJson(baseUrl, '/api/public/resolve-route', {}, authHeaders)
      const routeBody = await readJson(routeRes)
      assert.equal(routeRes.status, 400)
      assert.equal(routeBody.error, 'site_id_required')

      const pageRes = await postJson(
        baseUrl,
        '/api/public/page',
        { siteId: 'site-123' },
        bearerHeaders,
      )
      const pageBody = await readJson(pageRes)
      assert.equal(pageRes.status, 400)
      assert.equal(pageBody.error, 'page_id_or_slug_required')
    })

    await t.test('scheduler fallback path returns ao_read_failed when signer material is unavailable', async () => {
      const fallbackServer = await startServer({
        AO_PUBLIC_API_TOKEN: token,
        AO_DISABLE_DRYRUN: '1',
        AO_READ_FALLBACK_TO_SCHEDULER: '1',
      })
      try {
        const res = await postJson(
          fallbackServer.baseUrl,
          '/api/public/resolve-route',
          { siteId: 'site-contract', payload: { path: '/' } },
          authHeaders,
        )
        const body = await readJson(res)
        assert.equal(res.status, 502)
        assert.equal(body.ok, false)
        assert.equal(body.error, 'ao_read_failed')
        assert.match(
          String(body.message || ''),
          /(fallback_wallet_missing|arbundles_unavailable|scheduler_send_failed)/,
        )
      } finally {
        await stopServer(fallbackServer)
      }
    })
  } finally {
    await stopServer(server)
  }
})
