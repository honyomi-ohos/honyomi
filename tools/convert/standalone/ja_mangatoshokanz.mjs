// ja/mangatoshokanz — MangaToshokanZ (mangaz.com)
// Honest skip: viewer uses an RSA key exchange (client-generated keypair, RSA-encrypted
// page manifest, cookie ticket + __serial handshake). The plugin crypto DSL has no RSA.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'RSA key exchange for viewer manifest; crypto DSL has no RSA (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
