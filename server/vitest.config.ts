import { fileURLToPath } from 'node:url';
import { defineProject } from 'vitest/config';

export default defineProject({
  test: {
    name: 'server',
    globalSetup: [fileURLToPath(new URL('./test/global-setup.ts', import.meta.url))],
    testTimeout: 30_000,
    hookTimeout: 60_000,
  },
});
