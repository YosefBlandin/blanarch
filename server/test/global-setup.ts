import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PostgreSqlContainer } from '@testcontainers/postgresql';
import type { TestProject } from 'vitest/node';

declare module 'vitest' {
  export interface ProvidedContext {
    databaseUrl: string;
  }
}

const serverDir = fileURLToPath(new URL('..', import.meta.url));

// One throwaway Postgres per test run, migrated with the real `npm run migrate` script. Testcontainers'
// cleanup container removes it if the run crashes.
export default async function setup(project: TestProject): Promise<() => Promise<void>> {
  const container = await new PostgreSqlContainer('postgres:17.11').withStartupTimeout(60_000).start();
  const databaseUrl = container.getConnectionUri();
  try {
    execFileSync('npm', ['run', '--silent', 'migrate'], {
      cwd: serverDir,
      env: { ...process.env, DATABASE_URL: databaseUrl },
      stdio: ['ignore', 'ignore', 'inherit'],
    });
  } catch (err) {
    await container.stop();
    throw err;
  }
  project.provide('databaseUrl', databaseUrl);
  return async () => {
    await container.stop();
  };
}
