'use strict';
require('dotenv').config();

const express   = require('express');
const { Pool }  = require('pg');
const cors      = require('cors');
const path      = require('path');

const app  = express();
const PORT = process.env.APP_PORT || 3000;

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../frontend')));

// ── PostgreSQL connection pool ─────────────────────────────
const pool = new Pool({
  host:              process.env.DB_HOST     || 'localhost',
  port:              parseInt(process.env.DB_PORT || '5432', 10),
  user:              process.env.DB_USER     || 'appuser',
  password:          process.env.DB_PASSWORD || '',
  database:          process.env.DB_NAME     || 'appdb',
  max:               10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// ── Schema init ───────────────────────────────────────────
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS items (
      id         SERIAL PRIMARY KEY,
      name       VARCHAR(255) NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
  console.log('[DB] PostgreSQL schema ready');
}

// ── Routes ────────────────────────────────────────────────
app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', db: 'connected', timestamp: new Date().toISOString() });
  } catch (err) {
    res.status(503).json({ status: 'error', db: 'disconnected', error: err.message });
  }
});

app.get('/api/items', async (_req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT * FROM items ORDER BY created_at DESC'
    );
    res.json(rows);
  } catch (err) {
    console.error('[GET /api/items]', err.message);
    res.status(500).json({ error: 'Database error' });
  }
});

app.post('/api/items', async (req, res) => {
  try {
    const { name } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'name is required' });
    }
    const { rows } = await pool.query(
      'INSERT INTO items (name) VALUES ($1) RETURNING *',
      [name.trim()]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('[POST /api/items]', err.message);
    res.status(500).json({ error: 'Database error' });
  }
});

app.delete('/api/items/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM items WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    console.error('[DELETE /api/items]', err.message);
    res.status(500).json({ error: 'Database error' });
  }
});

// SPA fallback
app.get('*', (_req, res) =>
  res.sendFile(path.join(__dirname, '../frontend', 'index.html'))
);

// ── Start ─────────────────────────────────────────────────
initDB()
  .then(() => {
    app.listen(PORT, '0.0.0.0', () =>
      console.log(`[Server] Listening on http://0.0.0.0:${PORT}`)
    );
  })
  .catch((err) => {
    console.error('[Fatal] DB init failed:', err.message);
    process.exit(1);
  });

module.exports = app;
