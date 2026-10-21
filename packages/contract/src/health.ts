import { z } from 'zod';

/** Body of `GET /healthz`: 200 when the database answers within the time limit, 503 otherwise. */
export const HealthResponse = z.discriminatedUnion('status', [
  z.object({ status: z.literal('ok'), db: z.literal('up') }),
  z.object({ status: z.literal('unhealthy'), db: z.literal('down') }),
]);

export type HealthResponse = z.infer<typeof HealthResponse>;
