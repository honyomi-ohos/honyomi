// en/cmanhua — SKIP: site redesigned; old /danhsach list + Service.asmx endpoints return 404.
// New site (cmanhua.com) is a JS-rendered ASP.NET app; upstream ext targets the dead structure.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'site redesigned: /danhsach list and /Service.asmx/getchapter endpoints are 404; new site is JS-rendered and not scrapable with the upstream structure',
  };
}

export function generate() {
  throw new Error('skipped');
}
