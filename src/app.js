import { randomInt } from 'node:crypto'
import { existsSync, readFileSync } from 'node:fs'
import express from 'express'

// The commit this copy of the app was built from. The deploy script (module 05) puts it in
// src/commit.txt, so the smoke test can tell the new version from the one it replaced.
const commitFile = new URL('./commit.txt', import.meta.url)
const COMMIT = existsSync(commitFile) ? readFileSync(commitFile, 'utf8').trim() : null

const ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

function generateCode(length = 6) {
  let code = ''
  for (let position = 0; position < length; position++) {
    code += ALPHABET[randomInt(ALPHABET.length)]
  }
  return code
}

function isAbsoluteUrl(value) {
  if (typeof value !== 'string' || !URL.canParse(value)) {
    return false
  }
  const { protocol } = new URL(value)
  return protocol === 'http:' || protocol === 'https:'
}

// Builds the app around a store (see store.js), so the tests can hand it an
// in-memory database and the server a real one. `log` is where each request is
// written; the tests pass one that writes nothing.
export function createApp(store, { log = console.log } = {}) {
  const app = express()
  // Answers are indented, so they read well in a terminal. Real APIs often send them on one
  // line to save bytes, and a client formats them; this app is for learning.
  app.set('json spaces', 2)
  app.use(express.json())

  // One line per request, so `az webapp log tail` (module 04) shows each call.
  app.use((request, response, next) => {
    response.on('finish', () => {
      log(`${request.method} ${request.originalUrl} ${response.statusCode}`)
    })
    next()
  })

  app.get('/', (request, response) => {
    response.json({ app: 'Waypoint', status: 'running' })
  })

  // Used by App Service (module 04), by scripts/health-check.sh (modules 04 and 05) and
  // by the container (modules 07 and 09). Do not remove: later modules depend on this exact route.
  app.get('/health', (request, response) => {
    response.json({ status: 'healthy', version: '1.0.0', ...(COMMIT && { commit: COMMIT }) })
  })

  app.post('/links', async (request, response) => {
    const targetUrl = request.body?.targetUrl
    if (!isAbsoluteUrl(targetUrl)) {
      return response.status(400).json({ error: 'targetUrl must be an absolute URL' })
    }

    const link = await store.create({
      code: generateCode(),
      targetUrl,
      clicks: 0,
      createdAt: new Date().toISOString(),
    })

    response.status(201).location(`/links/${link.code}`).json(link)
  })

  app.get('/links/:code', async (request, response) => {
    const link = await store.findByCode(request.params.code)
    if (!link) {
      return response.status(404).json({ error: 'not found' })
    }
    response.json(link)
  })

  // The application's one real business endpoint: redirect a short code to
  // where it points, and count that it happened.
  app.get('/:code', async (request, response) => {
    const link = await store.findByCode(request.params.code)
    if (!link) {
      return response.status(404).json({ error: 'not found' })
    }
    await store.addClick(link.code)
    response.redirect(302, link.targetUrl)
  })

  return app
}
