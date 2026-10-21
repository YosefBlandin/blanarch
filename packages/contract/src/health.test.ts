import { describe, expect, it } from 'vitest';

import { HealthResponse } from './index.ts';

describe('HealthResponse', () => {
  it('T-CON-1: accepts the ok and unhealthy bodies', () => {
    expect(HealthResponse.parse({ status: 'ok', db: 'up' })).toEqual({ status: 'ok', db: 'up' });
    expect(HealthResponse.parse({ status: 'unhealthy', db: 'down' })).toEqual({ status: 'unhealthy', db: 'down' });
  });

  it('T-CON-1: rejects other status values and mixed bodies', () => {
    for (const body of [
      { status: 'degraded', db: 'up' },
      { status: 'ok', db: 'down' },
      { status: 'unhealthy', db: 'up' },
      { status: 'ok' },
      {},
    ]) {
      expect(HealthResponse.safeParse(body).success, JSON.stringify(body)).toBe(false);
    }
  });
});
