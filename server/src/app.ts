import Fastify, { type FastifyInstance } from 'fastify';
import { serializerCompiler, validatorCompiler, type ZodTypeProvider } from 'fastify-type-provider-zod';

import type { Config } from './config.ts';
import type { Db } from './db.ts';
import type { Database } from './db/types.ts';
import { healthRoutes } from './routes/health.ts';

export interface BuildOptions {
  /** Where JSON logs go; stdout when omitted. Tests pass a capture stream. */
  logStream?: { write(line: string): void };
}

/**
 * Builds the Fastify app without listening, so tests can call `app.inject()`. The caller owns the
 * database and closes it after `app.close()`.
 */
export async function buildApp(config: Config, db: Db<Database>, options: BuildOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: config.LOG_LEVEL,
      // Request logs carry method, url and headers, never the client address.
      serializers: {
        req: (req: { method: string; url: string; headers: Record<string, unknown> }) => ({
          method: req.method,
          url: req.url,
          headers: req.headers,
        }),
      },
      redact: ['req.headers.authorization', 'req.headers.cookie', 'req.headers["x-forwarded-for"]'],
      ...(options.logStream ? { stream: options.logStream } : {}),
    },
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  await app.register(healthRoutes(db.pool));
  await app.ready();
  return app;
}
