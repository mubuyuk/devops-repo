# Waypoint (Node.js)

A link shortener: create a short code for a URL, follow it, watch the click count go up. Small
on purpose, so that modules 04 to 12 are about the pipeline, the infrastructure and the operations
around it rather than about the application's own complexity.

Plain JavaScript on Express. No TypeScript and no build step: the code in `src/` is what runs.

No Dockerfile, Bicep or CI workflow ships with it. Writing those is the artefact for modules 07, 06
and 05.

## Run it locally

Needs Node.js 24 or later.

```
npm install
npm start
```

Uses a local `waypoint.db` Sqlite file with no further setup, through the Sqlite that is built into
Node. Listens on `http://localhost:3000`, or on the port in the `PORT` environment variable. Then:

```
curl http://localhost:3000/health
curl -X POST http://localhost:3000/links -H "Content-Type: application/json" \
  -d '{"targetUrl":"https://example.com"}'
curl -i http://localhost:3000/<code>          # redirects, counts the click
curl http://localhost:3000/links/<code>       # stats
```

The first line the app writes says which database it uses:

```
Waypoint is using Sqlite (waypoint.db)
Waypoint is listening on http://localhost:3000
```

Every request after that is one line, such as `POST /links 201`.

## Endpoints

| Method and path | What it does |
|---|---|
| `GET /` | `{"app":"Waypoint","status":"running"}` |
| `GET /health` | `{"status":"healthy","version":"1.0.0"}`, plus `"commit":"<sha>"` when the app was deployed with a `src/commit.txt` (module 05's deploy script adds it). Later modules depend on this exact route |
| `POST /links` | Body `{"targetUrl":"https://..."}`. Answers `201` with the new link, or `400` if the target is not an absolute `http` or `https` address |
| `GET /links/<code>` | The link and its click count, or `404` |
| `GET /<code>` | Redirects (`302`) to the target and counts the click, or `404` |

## Run the tests

```
npm test
```

Runs Node's own test runner (`node --test`) against an in-memory Sqlite database: no file, no real
database needed.

## Switching to Azure SQL Database

Set the `SQL_CONNECTION_STRING` environment variable (an App Setting in Azure, never committed
here) to the ADO.NET connection string the Azure Portal shows for the database:

```
Server=tcp:<server>.database.windows.net,1433;Database=<database>;User Id=<user>;Password=<password>;Encrypt=true
```

When it is set, the app uses SQL Server through the `mssql` package, and creates the `links` table
the first time it starts against an empty database. The first line in the log then says
`Waypoint is using SQL Server (...)`.

## Files

| | |
|---|---|
| `src/server.js` | Starts the app: picks the database and the port |
| `src/app.js` | The routes |
| `src/store.js` | Saving and reading links, in Sqlite or SQL Server |
| `tests/links.test.js` | The tests |
