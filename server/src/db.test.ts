import { sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, inject, it, vi } from 'vitest';

import { createDb } from './db.ts';

const databaseUrl = inject('databaseUrl');

describe('createDb', () => {
  const log = { error: vi.fn() };
  const { db, pool } = createDb(databaseUrl, log);

  afterAll(async () => {
    await db.destroy();
  });

  it('T-DB-1: the test container answers select 1 on Postgres 17.11', async () => {
    const { rows } = await sql<{
      one: number;
      version: string;
    }>`select 1 as one, current_setting('server_version') as version`.execute(db);
    expect(rows).toEqual([{ one: 1, version: expect.stringMatching(/^17\.11/) as unknown }]);
  });

  it('T-DB-2: a pool error is logged without the connection string and does not crash the process', async () => {
    // Terminate only this pool's own backend: other test files share the container and the application name.
    const { rows: own } = await pool.query<{ pid: number }>('select pg_backend_pid() as pid');
    expect(pool.totalCount).toBe(1);
    expect(pool.idleCount).toBe(1);

    const admin = new pg.Client({ connectionString: databaseUrl });
    await admin.connect();
    try {
      const { rows } = await admin.query<{ ok: boolean }>('select pg_terminate_backend($1) as ok', [own[0]?.pid]);
      expect(rows).toEqual([{ ok: true }]);
    } finally {
      await admin.end();
    }

    await vi.waitFor(() => expect(log.error).toHaveBeenCalled());
    const logged = JSON.stringify(log.error.mock.calls);
    const url = new URL(databaseUrl);
    for (const secret of [databaseUrl, url.password, url.host]) {
      expect(logged).not.toContain(secret);
    }

    const { rows } = await sql<{ one: number }>`select 1 as one`.execute(db);
    expect(rows).toEqual([{ one: 1 }]);
  });
});
