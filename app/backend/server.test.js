/**
 * API smoke tests — PostgreSQL mocked so no real DB is needed.
 * Run: npm test
 */
'use strict';

const request = require('supertest');

// Mock the pg Pool so tests run without a live PostgreSQL instance
jest.mock('pg', () => {
  const mQuery = jest.fn().mockResolvedValue({
    rows: [{ id: 1, name: 'Test Item', created_at: new Date().toISOString() }],
  });
  const mPool = { query: mQuery };
  return { Pool: jest.fn(() => mPool) };
});

const app = require('./server');

describe('GET /api/health', () => {
  it('returns 200 with status ok when DB responds', async () => {
    const res = await request(app).get('/api/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.db).toBe('connected');
  });
});

describe('GET /api/items', () => {
  it('returns an array', async () => {
    const res = await request(app).get('/api/items');
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });
});

describe('POST /api/items', () => {
  it('returns 400 when name is empty', async () => {
    const res = await request(app)
      .post('/api/items')
      .send({ name: '' });
    expect(res.statusCode).toBe(400);
  });

  it('returns 400 when name is missing', async () => {
    const res = await request(app)
      .post('/api/items')
      .send({});
    expect(res.statusCode).toBe(400);
  });
});
