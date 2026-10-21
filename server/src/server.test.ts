import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:net';
import { fileURLToPath } from 'node:url';
import { describe, expect, inject, it, vi } from 'vitest';

// These tests start the real entry point with plain `node`, so they also prove that Node's type stripping
// loads the server and the workspace contract package (RK-2).
const entry = fileURLToPath(new URL('./server.ts', import.meta.url));
const databaseUrl = inject('databaseUrl');

async function freePort(): Promise<number> {
  const probe = createServer();
  probe.listen(0, '127.0.0.1');
  await once(probe, 'listening');
  const address = probe.address();
  probe.close();
  if (address === null || typeof address === 'string') throw new Error('no port');
  return address.port;
}

function start(env: Record<string, string>) {
  const inherited = { ...process.env };
  delete inherited.DATABASE_URL;
  const child = spawn(process.execPath, [entry], {
    env: { ...inherited, HOST: '127.0.0.1', LOG_LEVEL: 'info', ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk: Buffer) => (output.stdout += chunk.toString('utf8')));
  child.stderr.on('data', (chunk: Buffer) => (output.stderr += chunk.toString('utf8')));
  const exited = new Promise<number | null>((resolve) => child.on('exit', resolve));
  return { child, output, exited };
}

describe('server entry', () => {
  it('T-SRV-1: starting with invalid config exits 1 before the port opens', async () => {
    const port = await freePort();
    const { output, exited } = start({ PORT: String(port) });

    expect(await exited).toBe(1);
    expect(output.stderr).toMatch(/^config: DATABASE_URL is required$/m);
    expect(output.stdout).not.toMatch(/listening/i);
  });

  it('T-SRV-2: the server started with plain node answers /healthz, and SIGTERM exits 0', async () => {
    const port = await freePort();
    const { child, output, exited } = start({ PORT: String(port), DATABASE_URL: databaseUrl });

    try {
      await vi.waitFor(() => expect(output.stdout).toMatch(/Server listening/), { timeout: 15_000, interval: 50 });
      const res = await fetch(`http://127.0.0.1:${port}/healthz`);
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({ status: 'ok', db: 'up' });

      child.kill('SIGTERM');
      expect(await exited, output.stderr).toBe(0);
    } finally {
      child.kill('SIGKILL');
    }
  });
});
