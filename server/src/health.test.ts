import { Writable } from 'node:stream';
import pg from 'pg';
import { afterAll, describe, expect, inject, it, vi } from 'vitest';

import { buildApp } from './app.ts';
import type { Config } from './config.ts';
import { APPLICATION_NAME, createDb } from './db.ts';
import type { Database } from './db/types.ts';

const databaseUrl = inject('databaseUrl');

function configFor(url: string): Config {
  return { NODE_ENV: 'test', HOST: '127.0.0.1', PORT: 3000, DATABASE_URL: url, LOG_LEVEL: 'info' };
}

/** Collects the app's JSON log lines instead of printing them. */
function logCapture() {
  const lines: string[] = [];
  const stream = new Writable({
    write(chunk: Buffer, _encoding, done) {
      lines.push(...chunk.toString('utf8').split('\n').filter(Boolean));
      done();
    },
  });
  return { stream, lines };
}

async function setup(url: string) {
  const log = logCapture();
  const poolLog = { error: vi.fn() };
  const db = createDb<Database>(url, poolLog);
  const app = await buildApp(configFor(url), db, { logStream: log.stream });
  return { app, db, log, poolLog };
}

describe('GET /healthz', () => {
  const cleanups: (() => Promise<unknown>)[] = [];
  afterAll(async () => {
    for (const cleanup of cleanups) await cleanup();
  });

  it('T-HLT-1: a healthy database gives 200 with the ok body', async () => {
    const { app, db } = await setup(databaseUrl);
    cleanups.push(
      () => app.close(),
      () => db.db.destroy(),
    );

    const res = await app.inject({ method: 'GET', url: '/healthz' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok', db: 'up' });
  });

  it('T-HLT-2: an unreachable database gives 503 in under 1500 ms with no host or driver text', async () => {
    const unreachable = 'postgres://app:s3cret-pw@192.0.2.1:5432/app';
    const { app, db, log } = await setup(unreachable);
    cleanups.push(
      () => app.close(),
      () => db.db.destroy(),
    );

    const started = performance.now();
    const res = await app.inject({ method: 'GET', url: '/healthz' });
    const elapsed = performance.now() - started;

    expect(res.statusCode).toBe(503);
    expect(elapsed).toBeLessThan(1500);
    expect(res.body).toBe(JSON.stringify({ status: 'unhealthy', db: 'down' }));
    for (const text of ['192.0.2.1', 's3cret-pw', unreachable]) {
      expect(log.lines.join('\n')).not.toContain(text);
    }
  });

  it('T-HLT-3: after the pooled backends are terminated, the process stays up and the next call gives 200', async () => {
    const { app, db, poolLog } = await setup(databaseUrl);
    cleanups.push(
      () => app.close(),
      () => db.db.destroy(),
    );

    expect((await app.inject({ method: 'GET', url: '/healthz' })).statusCode).toBe(200);
    expect(db.pool.idleCount).toBeGreaterThan(0);

    const admin = new pg.Client({ connectionString: databaseUrl });
    await admin.connect();
    try {
      await admin.query(`select pg_terminate_backend(pid) from pg_stat_activity where application_name = $1`, [
        APPLICATION_NAME,
      ]);
    } finally {
      await admin.end();
    }
    await vi.waitFor(() => expect(poolLog.error).toHaveBeenCalled());

    const res = await app.inject({ method: 'GET', url: '/healthz' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok', db: 'up' });
  });

  it('T-HLT-4: authorization and cookie headers appear redacted in the request log', async () => {
    const { app, db, log } = await setup(databaseUrl);
    cleanups.push(
      () => app.close(),
      () => db.db.destroy(),
    );

    await app.inject({
      method: 'GET',
      url: '/healthz',
      headers: { authorization: 'Bearer tok-abc123', cookie: 'sid=cookie-xyz789' },
    });

    const incoming = log.lines
      .map((line) => JSON.parse(line) as { msg?: string; req?: { headers?: Record<string, string> } })
      .find((entry) => entry.msg === 'incoming request');
    expect(incoming?.req?.headers).toMatchObject({ authorization: '[Redacted]', cookie: '[Redacted]' });
    const all = log.lines.join('\n');
    expect(all).not.toContain('tok-abc123');
    expect(all).not.toContain('cookie-xyz789');
  });
});
