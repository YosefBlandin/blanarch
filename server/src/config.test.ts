import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from 'vitest';

import { loadConfig } from './config.ts';

const DATABASE_URL = 'postgres://app:s3cret-pw@db.example.com:5432/app';

class ExitError extends Error {}

describe('loadConfig', () => {
  let exit: MockInstance<typeof process.exit>;
  let stderr: string;

  beforeEach(() => {
    stderr = '';
    exit = vi.spyOn(process, 'exit').mockImplementation((code) => {
      throw new ExitError(`exit ${String(code)}`);
    });
    vi.spyOn(process.stderr, 'write').mockImplementation((chunk: string | Uint8Array) => {
      stderr += String(chunk);
      return true;
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('T-CFG-1: parses a valid environment with the documented defaults', () => {
    expect(loadConfig({ DATABASE_URL })).toEqual({
      NODE_ENV: 'development',
      HOST: '127.0.0.1',
      PORT: 3000,
      DATABASE_URL,
      LOG_LEVEL: 'info',
    });
    expect(
      loadConfig({ DATABASE_URL, NODE_ENV: 'test', HOST: '0.0.0.0', PORT: '8080', LOG_LEVEL: 'debug' }),
    ).toMatchObject({ NODE_ENV: 'test', HOST: '0.0.0.0', PORT: 8080, LOG_LEVEL: 'debug' });
    expect(exit).not.toHaveBeenCalled();
  });

  it('T-CFG-2: a missing DATABASE_URL exits 1 and names it', () => {
    expect(() => loadConfig({})).toThrow(ExitError);
    expect(exit).toHaveBeenCalledWith(1);
    expect(stderr).toMatch(/^config: DATABASE_URL is required$/m);
  });

  it('T-CFG-3: an invalid PORT with a DATABASE_URL set prints no setting value', () => {
    expect(() => loadConfig({ DATABASE_URL, PORT: '70000', LOG_LEVEL: 'loud' })).toThrow(ExitError);
    expect(exit).toHaveBeenCalledWith(1);
    expect(stderr).toMatch(/^config: PORT /m);
    expect(stderr).toMatch(/^config: LOG_LEVEL /m);
    for (const value of [DATABASE_URL, 's3cret-pw', 'db.example.com', '70000', 'loud']) {
      expect(stderr).not.toContain(value);
    }
  });

  it('T-CFG-3: a DATABASE_URL that is not a postgres URL is rejected without printing it', () => {
    const wrong = 'mysql://app:s3cret-pw@db.example.com/app';
    expect(() => loadConfig({ DATABASE_URL: wrong })).toThrow(ExitError);
    expect(stderr).toMatch(/^config: DATABASE_URL /m);
    expect(stderr).not.toContain('s3cret-pw');
    expect(stderr).not.toContain('db.example.com');
  });
});
