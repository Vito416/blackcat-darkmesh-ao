#!/usr/bin/env node
import fs from 'fs'
import path from 'path'

const distDir = path.resolve('dist')
if (!fs.existsSync(distDir)) {
  console.error('dist/ not found; build first')
  process.exit(1)
}

const seedPattern =
  /chance\.seed\(tonumber\(msg\['Block-Height'\]\s*\.\.\s*stringToSeed\(msg\.Owner\s*\.\.\s*msg\.Module\s*\.\.\s*msg\.Id\)\)\)/
const templatesPattern = /local _bundled = require\("templates"\)/
const seedPatchedPattern =
  /chance\.seed\(tonumber\(msg\['Block-Height'\]\s*\.\.\s*stringToSeed\(ownerTag\s*\.\.\s*moduleTag\s*\.\.\s*idTag\)\)\)/
const templatesPatchedPattern = /local _ok_templates,\s*_bundled = pcall\(require,\s*"templates"\)/

const replacement = `local moduleTag = msg.Module\n    if not moduleTag and env and env.Process and env.Process.Tags then\n      for _, t in ipairs(env.Process.Tags) do\n        if t.name == "Module" then\n          moduleTag = t.value\n          break\n        end\n      end\n    end\n    moduleTag = moduleTag or ''\n    local ownerTag = msg.Owner or msg.From or ''\n    local idTag = msg.Id or (env and env.Process and env.Process.Id) or ''\n    chance.seed(tonumber(msg['Block-Height'] .. stringToSeed(ownerTag .. moduleTag .. idTag)))`

const defaultTemplatesStub = `-- Stub templates module for AO processes; process.lua expects require("templates").\n-- No UI templates are bundled in AO processes, so return empty table.\nlocal M = {}\nreturn M\n`
const templatesSrcPath = path.resolve('ao/templates.lua')
const templatesSrc = fs.existsSync(templatesSrcPath)
  ? fs.readFileSync(templatesSrcPath, 'utf8')
  : defaultTemplatesStub

let patchedSeed = 0
let patchedTemplates = 0
let seedAlreadyPatched = 0
let templatesAlreadyPatched = 0
let copiedTemplates = 0
for (const entry of fs.readdirSync(distDir, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue
  const target = path.join(distDir, entry.name, 'process.lua')
  if (!fs.existsSync(target)) continue

  const templatesTarget = path.join(distDir, entry.name, 'templates.lua')
  fs.writeFileSync(templatesTarget, templatesSrc)
  copiedTemplates += 1
  console.log(`wrote ${templatesTarget}`)

  const src = fs.readFileSync(target, 'utf8')
  let next = src
  let changed = false

  if (seedPattern.test(next)) {
    next = next.replace(seedPattern, replacement)
    patchedSeed += 1
    changed = true
  } else if (seedPatchedPattern.test(next)) {
    seedAlreadyPatched += 1
  }

  if (templatesPattern.test(next)) {
    next = next.replace(
      templatesPattern,
      'local _ok_templates, _bundled = pcall(require, "templates")\n      if not _ok_templates then _bundled = {} end'
    )
    patchedTemplates += 1
    changed = true
  } else if (templatesPatchedPattern.test(next)) {
    templatesAlreadyPatched += 1
  }

  if (changed) {
    fs.writeFileSync(target, next)
    console.log(`patched ${target}`)
  }
}

if (!patchedSeed && !seedAlreadyPatched) {
  console.error('Warning: no process.lua files matched the seed patch pattern.')
}

if (!patchedTemplates && !templatesAlreadyPatched) {
  console.error('Warning: no process.lua files matched the templates patch pattern.')
}

if (!patchedSeed && !patchedTemplates && !copiedTemplates) {
  console.error('No dist/<process>/process.lua targets found.');
  process.exit(2)
}
