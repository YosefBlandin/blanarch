import { buildApp } from './app.ts';
import { loadConfig } from './config.ts';
import { createDb } from './db.ts';
import type { Database } from './db/types.ts';

/** How long in-flight requests get to finish after SIGTERM or SIGINT before a forced exit. */
const SHUTDOWN_GRACE_MS = 10_000;

/**
 * Loads config (exits 1 before listening when it is invalid), builds the app and listens. SIGTERM or
 * SIGINT closes the server and the pool and exits 0, or exits 1 after the grace period.
 */
export async function main(): Promise<void> {
  const config = loadConfig();
  // Pool errors need a connection, so none can arrive before the app (and its logger) exists.
  const db = createDb<Database>(config.DATABASE_URL, {
    error: (obj, msg) => server.log.error(obj, msg),
  });
  const server = await buildApp(config, db);

  let stopping = false;
  const shutdown = (signal: NodeJS.Signals) => {
    if (stopping) return;
    stopping = true;
    server.log.info({ signal }, 'shutting down');
    setTimeout(() => {
      server.log.error('shutdown timed out');
      process.exit(1);
    }, SHUTDOWN_GRACE_MS).unref();
    server
      .close()
      .then(() => db.db.destroy())
      .then(
        () => process.exit(0),
        (err: unknown) => {
          server.log.error({ code: (err as { code?: string }).code ?? 'unknown' }, 'shutdown failed');
          process.exit(1);
        },
      );
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);

  try {
    await server.listen({ host: config.HOST, port: config.PORT });
  } catch (err) {
    server.log.error({ code: (err as { code?: string }).code ?? 'unknown' }, 'listen failed');
    await db.db.destroy();
    process.exit(1);
  }
}

if (import.meta.main) await main();
