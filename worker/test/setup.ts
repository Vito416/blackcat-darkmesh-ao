import { afterAll, vi } from 'vitest'

// Ensure miniflare processes shut down cleanly
afterAll(async () => {
  // noop hook if we need future cleanup
})

vi.setConfig({
  testTimeout: 30000,
  pool: 'forks',
  maxThreads: 1,
})
