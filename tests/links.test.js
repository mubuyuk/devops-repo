import { after, before, test } from 'node:test'
import assert from 'node:assert/strict'
import { createApp } from '../src/app.js'
import { openSqliteStore } from '../src/store.js'

// An in-memory database for the tests, the same reason module 03's CI pipeline
// can run the tests before Azure exists at all (module 04).
let server
let baseUrl

before(async () => {
  const app = createApp(openSqliteStore(':memory:'), { log: () => {} })
  await new Promise((resolve) => {
    // Port 0 lets the system pick a free port.
    server = app.listen(0, resolve)
  })
  baseUrl = `http://localhost:${server.address().port}`
})

after(() => {
  server.close()
})

function createLink(targetUrl) {
  return fetch(`${baseUrl}/links`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ targetUrl }),
  })
}

test('health returns ok', async () => {
  const response = await fetch(`${baseUrl}/health`)
  assert.equal(response.status, 200)
})

test('create a link, then look it up: the same target comes back', async () => {
  const create = await createLink('https://example.com/a')
  assert.equal(create.status, 201)
  const { code } = await create.json()

  const lookup = await fetch(`${baseUrl}/links/${code}`)
  assert.equal(lookup.status, 200)
  const body = await lookup.json()
  assert.equal(body.targetUrl, 'https://example.com/a')
  assert.equal(body.clicks, 0)
})

test('visiting a code redirects and counts the click', async () => {
  const create = await createLink('https://example.com/b')
  const { code } = await create.json()

  const visit = await fetch(`${baseUrl}/${code}`, { redirect: 'manual' })
  assert.equal(visit.status, 302)
  assert.equal(visit.headers.get('location'), 'https://example.com/b')

  const lookup = await fetch(`${baseUrl}/links/${code}`)
  assert.equal((await lookup.json()).clicks, 1)
})

test('an unknown code returns not found', async () => {
  const response = await fetch(`${baseUrl}/does-not-exist`)
  assert.equal(response.status, 404)
})

test('rejects a target that is not an absolute URL', async () => {
  const response = await createLink('not-a-url')
  assert.equal(response.status, 400)
})
