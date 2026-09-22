// ar/duskoryvile — SKIP: the site requires a WordPress login for ALL content
// (unauthenticated /series-list/ redirects to /login/?redirect_to=...). The upstream
// extension logs in via user-configured username/password preferences, which the
// plugin host cannot provide.
export function extract(ctx) {
  return {
    ok: false,
    reason: 'login required for all content (site redirects unauthenticated requests to /login); credentials preference not portable',
  };
}

export function generate() {
  return '';
}
