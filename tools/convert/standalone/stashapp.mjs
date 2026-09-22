// all/stashapp — SKIPPED: self-hosted Stash server source.
// Default baseUrl is http://localhost:9999 (user's own Stash instance) and requires a
// user-configured API key header. A plugin with a fixed manifest baseUrl + no settings
// support cannot reach any real server, so an honest port is impossible.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'self-hosted Stash server (default baseUrl http://localhost:9999 + user API key preference); fixed-baseUrl plugin would be unusable',
  };
}

export function generate() {
  return '';
}
