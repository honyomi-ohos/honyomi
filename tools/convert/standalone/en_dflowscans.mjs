// en/dflowscans — SKIP: site dead (dflow.alwaysdata.net returns "Site not found")
export const runtime = 'wp';

export function extract(ctx) {
  return { ok: false, reason: 'site dead: dflow.alwaysdata.net returns 404 "Site not found" (hosting expired)' };
}

export function generate() {
  throw new Error('skipped');
}
