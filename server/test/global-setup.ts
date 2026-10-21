import { PostgreSqlContainer } from '@testcontainers/postgresql';
import type { TestProject } from 'vitest/node';

declare module 'vitest' {
  export interface ProvidedContext {
    databaseUrl: string;
  }
}

// One throwaway Postgres per test run. Testcontainers' cleanup container removes it if the run crashes.
export default async function setup(project: TestProject): Promise<() => Promise<void>> {
  const container = await new PostgreSqlContainer('postgres:17.11').withStartupTimeout(60_000).start();
  project.provide('databaseUrl', container.getConnectionUri());
  return async () => {
    await container.stop();
  };
}
