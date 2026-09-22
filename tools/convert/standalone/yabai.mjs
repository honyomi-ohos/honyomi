// all/yabai — SKIP: site (yabai.si) is protected by DDOS-Guard; every session must solve
// the JS challenge via WebView before tokens (XSRF-TOKEN + Inertia version) can be read.
// The plugin host HTTP DSL cannot execute the challenge, so all requests 403.
export function extract(ctx) {
  return {
    ok: false,
    reason: 'DDOS-Guard JS challenge on every session; requires WebView cookie solving that the plugin host cannot perform',
  };
}

export function generate() {
  return '';
}
