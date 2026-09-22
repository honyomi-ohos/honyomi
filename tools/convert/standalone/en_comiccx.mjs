// en/comiccx — SKIP: site rebuilt as SPA; upstream /api/manga endpoints return {"error":"No such endpoint."}
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'site rebuilt: /api/manga endpoint removed (404 "No such endpoint"); new SPA exposes no portable manga API',
  };
}

export function generate() {
  throw new Error('skipped');
}
