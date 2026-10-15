import { DatabaseSync } from 'node:sqlite'

// Local, zero-setup default: a Sqlite file next to the app, using the Sqlite that is
// built into Node. Set SQL_CONNECTION_STRING (an App Setting in Azure, never a value
// committed to the repo) to switch to Azure SQL Database without touching this code.
export async function openStore(connectionString = process.env.SQL_CONNECTION_STRING) {
  if (connectionString) {
    return openSqlServerStore(connectionString)
  }
  return openSqliteStore('waypoint.db')
}

function toLink(row) {
  return {
    code: row.code,
    targetUrl: row.target_url,
    clicks: row.clicks,
    createdAt: new Date(row.created_at).toISOString(),
  }
}

// `filename` can be ':memory:', which is what the tests use.
export function openSqliteStore(filename) {
  const database = new DatabaseSync(filename)
  database.exec(`
    CREATE TABLE IF NOT EXISTS links (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      target_url TEXT NOT NULL,
      clicks INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  `)

  const insert = database.prepare(
    'INSERT INTO links (code, target_url, clicks, created_at) VALUES (?, ?, ?, ?)',
  )
  const selectByCode = database.prepare('SELECT * FROM links WHERE code = ?')
  const incrementClicks = database.prepare('UPDATE links SET clicks = clicks + 1 WHERE code = ?')

  return {
    description: `Sqlite (${filename})`,
    async create(link) {
      insert.run(link.code, link.targetUrl, link.clicks, link.createdAt)
      return link
    },
    async findByCode(code) {
      const row = selectByCode.get(code)
      return row ? toLink(row) : null
    },
    async addClick(code) {
      incrementClicks.run(code)
    },
    async close() {
      database.close()
    },
  }
}

// Azure SQL Database. The connection string is the ADO.NET one the Azure Portal shows:
// Server=tcp:<server>.database.windows.net,1433;Database=<database>;User Id=<user>;Password=<password>;Encrypt=true
async function openSqlServerStore(connectionString) {
  const { default: sql } = await import('mssql')
  const pool = await sql.connect(connectionString)

  // Creates the table the first time the app starts against a new database.
  await pool.request().query(`
    IF OBJECT_ID(N'links', N'U') IS NULL
    CREATE TABLE links (
      id INT IDENTITY PRIMARY KEY,
      code NVARCHAR(450) NOT NULL UNIQUE,
      target_url NVARCHAR(MAX) NOT NULL,
      clicks INT NOT NULL DEFAULT 0,
      created_at DATETIMEOFFSET NOT NULL
    )
  `)

  return {
    description: `SQL Server (${pool.config.server}, database ${pool.config.database})`,
    async create(link) {
      await pool.request()
        .input('code', sql.NVarChar(450), link.code)
        .input('targetUrl', sql.NVarChar(sql.MAX), link.targetUrl)
        .input('clicks', sql.Int, link.clicks)
        .input('createdAt', sql.DateTimeOffset, new Date(link.createdAt))
        .query(
          'INSERT INTO links (code, target_url, clicks, created_at) VALUES (@code, @targetUrl, @clicks, @createdAt)',
        )
      return link
    },
    async findByCode(code) {
      const result = await pool.request()
        .input('code', sql.NVarChar(450), code)
        .query('SELECT * FROM links WHERE code = @code')
      const row = result.recordset[0]
      return row ? toLink(row) : null
    },
    async addClick(code) {
      await pool.request()
        .input('code', sql.NVarChar(450), code)
        .query('UPDATE links SET clicks = clicks + 1 WHERE code = @code')
    },
    async close() {
      await pool.close()
    },
  }
}
