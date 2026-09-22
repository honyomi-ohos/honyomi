// pt/rfdragonscan — Next.js server-action source:
// 1) the ext's hardcoded next-action IDs are stale against the live site
//    (POST returns 404 "Server action not found"), so details/chapters are unobtainable;
// 2) chapter reader now redirects to /login even for free chapters (account required).
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'server-action IDs rotated (details/chapters 404) and reading requires account login',
  };
}

export function generate() {
  throw new Error('not convertible');
}
