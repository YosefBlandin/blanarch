import { z } from 'zod';

const Settings = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().min(1).default('127.0.0.1'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.url({ protocol: /^postgres(ql)?$/, error: 'must be a postgres:// URL' }),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
});

export type Config = z.infer<typeof Settings>;

/**
 * Parses the server settings from the environment. On any invalid setting it prints one
 * `config: <NAME> <reason>` line per issue to stderr and exits 1. Setting values are never printed,
 * since DATABASE_URL holds the password.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const result = Settings.safeParse(env, { reportInput: false });
  if (result.success) return result.data;

  for (const issue of result.error.issues) {
    const name = issue.path.join('.');
    const reason = env[name] === undefined ? 'is required' : issue.message;
    process.stderr.write(`config: ${name} ${reason}\n`);
  }
  process.exit(1);
}
