import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import { afterAll, describe, expect, inject, it, vi } from 'vitest';

// These tests drive the real `npm run migrate` script against fixture folders, each in a fresh database.
const serverDir = fileURLToPath(new URL('..', import.meta.url));
const containerUrl = inject('databaseUrl');
const scratch = mkdtempSync(join(tmpdir(), 'migrations-test-'));

afterAll(() => {
  rmSync(scratch, { recursive: true, force: true });
});

async function query<T extends pg.QueryResultRow>(url: string, text: string): Promise<T[]> {
  const client = new pg.Client({ connectionString: url });
  await client.connect();
  try {
    return (await client.query<T>(text)).rows;
  } finally {
    await client.end();
  }
}

async function freshDatabase(): Promise<string> {
  const name = `mig_${randomUUID().replaceAll('-', '')}`;
  await query(containerUrl, `create database ${name}`);
  const url = new URL(containerUrl);
  url.pathname = `/${name}`;
  return url.toString();
}

function fixture(files: Record<string, string>): string {
  const dir = mkdtempSync(join(scratch, 'fixture-'));
  for (const [name, sql] of Object.entries(files)) writeFileSync(join(dir, name), sql);
  return dir;
}

const migration = (up: string, down = '') => `-- Up Migration\n${up}\n\n-- Down Migration\n${down}\n`;

function migrateArgs(dir: string): string[] {
  return ['run', '--silent', 'migrate', '--', '--migrations-dir', dir];
}

function migrate(url: string, dir: string): { code: number | null; out: string } {
  const r = spawnSync('npm', migrateArgs(dir), {
    cwd: serverDir,
    env: { ...process.env, DATABASE_URL: url },
    encoding: 'utf8',
  });
  return { code: r.status, out: `${r.stdout}${r.stderr}` };
}

async function applied(url: string): Promise<string[]> {
  const [exists] = await query<{ t: string | null }>(url, `select to_regclass('public.pgmigrations') as t`);
  if (!exists?.t) return [];
  const rows = await query<{ name: string }>(url, 'select name from pgmigrations order by id');
  return rows.map((r) => r.name);
}

async function tables(url: string): Promise<string[]> {
  const rows = await query<{ table_name: string }>(
    url,
    `select table_name from information_schema.tables where table_schema = 'public' and table_name <> 'pgmigrations' order by 1`,
  );
  return rows.map((r) => r.table_name);
}

describe('migrate', () => {
  it('T-MIG-1: applies pending migrations in order, once; a second run applies nothing', async () => {
    const url = await freshDatabase();
    const dir = fixture({
      '1_first.sql': migration('create table first (id int primary key);', 'drop table first;'),
      '2_second.sql': migration('create table second (id int references first (id));', 'drop table second;'),
    });

    const first = migrate(url, dir);
    expect(first.code, first.out).toBe(0);
    expect(await applied(url)).toEqual(['1_first', '2_second']);
    expect(await tables(url)).toEqual(['first', 'second']);

    const second = migrate(url, dir);
    expect(second.code, second.out).toBe(0);
    expect(second.out).toMatch(/No migrations to run/);
    expect(await applied(url)).toEqual(['1_first', '2_second']);
  });

  it('T-MIG-2: a failing second file leaves neither file applied and exits 1', async () => {
    const url = await freshDatabase();
    const dir = fixture({
      '1_good.sql': migration('create table good (id int);', 'drop table good;'),
      '2_bad.sql': migration('select * from no_such_table;'),
    });

    const r = migrate(url, dir);
    expect(r.code, r.out).toBe(1);
    expect(r.out).toMatch(/no_such_table/);
    expect(await applied(url)).toEqual([]);
    expect(await tables(url)).toEqual([]);
  });

  it('T-MIG-3: a run while another holds the lock exits 1 with nothing applied', async () => {
    const url = await freshDatabase();
    const dbName = new URL(url).pathname.slice(1);
    const dir = fixture({
      '1_slow.sql': migration('select pg_sleep(4);\ncreate table slow (id int);', 'drop table slow;'),
    });

    const holder = spawn('npm', migrateArgs(dir), {
      cwd: serverDir,
      env: { ...process.env, DATABASE_URL: url },
      stdio: 'ignore',
    });
    const holderExit = new Promise<number | null>((resolve) => holder.on('exit', resolve));

    await vi.waitFor(
      async () => {
        const locks = await query<{ n: number }>(
          url,
          `select count(*)::int as n from pg_locks l join pg_database d on d.oid = l.database
           where l.locktype = 'advisory' and l.granted and d.datname = '${dbName}'`,
        );
        expect(locks[0]?.n).toBeGreaterThan(0);
      },
      { timeout: 10_000, interval: 100 },
    );

    const second = migrate(url, dir);
    expect(second.code, second.out).toBe(1);
    expect(await applied(url)).toEqual([]);

    expect(await holderExit).toBe(0);
    expect(await applied(url)).toEqual(['1_slow']);
  });
});
