import { Kysely, PostgresDialect } from 'kysely';
import pg from 'pg';

/** The part of a pino or Fastify logger that createDb uses. */
export interface DbLogger {
  error(obj: object, msg: string): void;
}

export interface Db<DB> {
  db: Kysely<DB>;
  pool: pg.Pool;
}

/** Name the server's connections carry in pg_stat_activity. */
export const APPLICATION_NAME = 'blanarch-server';

/**
 * One pg pool and a Kysely instance on it. Pass the schema type, usually `Database` from db/types.ts.
 * An idle connection that drops (for example on a database restart) emits a pool error; it is logged by
 * code only, never with the connection string or host, and the process keeps running. Checkouts give up
 * after connectionTimeoutMillis instead of waiting forever.
 */
export function createDb<DB>(databaseUrl: string, log: DbLogger): Db<DB> {
  const pool = new pg.Pool({
    connectionString: databaseUrl,
    application_name: APPLICATION_NAME,
    connectionTimeoutMillis: 5_000,
  });
  pool.on('error', (err: Error & { code?: string }) => {
    log.error({ code: err.code ?? 'unknown' }, 'database pool error');
  });
  return { db: new Kysely<DB>({ dialect: new PostgresDialect({ pool }) }), pool };
}
