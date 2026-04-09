import { defineConfig } from '@memetic-block/hyperengine'

export default defineConfig({
  processes: {
    registry: {
      entry: 'dist/registry-bundle.lua',
      type: 'process'
    },
    site: {
      entry: 'dist/site-bundle.lua',
      type: 'process'
    },
    catalog: {
      entry: 'dist/catalog-bundle.lua',
      type: 'process'
    },
    access: {
      entry: 'dist/access-bundle.lua',
      type: 'process'
    },
    ingest: {
      entry: 'dist/ingest-bundle.lua',
      type: 'process'
    }
  },
  aos: {
    commit: 'd5ff8f44df752b13a1e7bce3ded2a5d84b69287f',
    target: 64,
    stack_size: 3_145_728,
    initial_memory: 4_194_304,
    maximum_memory: 1_073_741_824,
    compute_limit: '9000000000000',
    module_format: 'wasm64-unknown-emscripten-draft_2024_02_15',
    exclude: []
  },
  deploy: {
    enabled: false
  }
})
