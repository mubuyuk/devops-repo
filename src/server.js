import { createApp } from './app.js'
import { openStore } from './store.js'

// App Service and Container Apps tell the app which port to listen on through PORT.
const port = Number(process.env.PORT ?? 3000)

const store = await openStore()
console.log(`Waypoint is using ${store.description}`)
const app = createApp(store)

app.listen(port, () => {
  console.log(`Waypoint is listening on http://localhost:${port}`)
})
