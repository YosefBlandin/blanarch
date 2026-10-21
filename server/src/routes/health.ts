import { HealthResponse } from '@blanarch/contract';
import type { FastifyBaseLogger } from 'fastify';
import type { FastifyPluginCallbackZod } from 'fastify-type-provider-zod';
import type pg from 'pg';

/** Total time for a pooled connection plus `select 1`. */
export const HEALTH_TIMEOUT_MS = 1_000;

/**
 * Checks out a connection and runs `select 1` under one timer. When the timer fires first, the probe
 * reports down at once and the connection is released as soon as it is no longer in use: destroyed if a
 * query was running on it, returned to the pool if the checkout finishes late.
 */
async function probe(pool: pg.Pool, log: FastifyBaseLogger): Promise<boolean> {
  let timedOut = false;
  let active: pg.PoolClient | undefined;
  let timer: NodeJS.Timeout | undefined;

  const work = (async () => {
    const client = await pool.connect();
    if (timedOut) {
      client.release();
      return false;
    }
    active = client;
    try {
      await client.query('select 1');
      return true;
    } finally {
      active = undefined;
      if (!timedOut) client.release();
    }
  })();

  const deadline = new Promise<false>((resolve) => {
    timer = setTimeout(() => {
      timedOut = true;
      active?.release(true);
      log.warn({ reason: 'timeout' }, 'health check: database down');
      resolve(false);
    }, HEALTH_TIMEOUT_MS);
  });

  // Log by error code only: driver messages can carry the host.
  const guarded = work.catch((err: unknown) => {
    if (!timedOut) log.warn({ code: (err as { code?: string }).code ?? 'unknown' }, 'health check: database down');
    return false;
  });

  try {
    return await Promise.race([guarded, deadline]);
  } finally {
    clearTimeout(timer);
  }
}

/** `GET /healthz`: unversioned operations endpoint. */
export function healthRoutes(pool: pg.Pool): FastifyPluginCallbackZod {
  return (app, _options, done) => {
    app.get(
      '/healthz',
      { schema: { response: { 200: HealthResponse, 503: HealthResponse } } },
      async (request, reply) => {
        if (await probe(pool, request.log)) return { status: 'ok', db: 'up' } as const;
        return reply.code(503).send({ status: 'unhealthy', db: 'down' });
      },
    );
    done();
  };
}
