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
    await sql`select 1`.execute(db);
    expect(pool.idleCount).toBeGreaterThan(0);

    const admin = new pg.Client({ connectionString: databaseUrl });
    await admin.connect();
    try {
      const { rowCount } = await admin.query(
        `select pg_terminate_backend(pid) from pg_stat_activity where application_name = 'blanarch-server'`,
      );
      expect(rowCount).toBeGreaterThan(0);
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
