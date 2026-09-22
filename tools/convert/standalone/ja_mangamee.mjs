// ja/mangamee — MangaMee (official app)
// Honest skip: page images are XOR-encrypted with a per-page hex key delivered via a
// protobuf API; decryption needs a byte-level OkHttp interceptor the JS plugin runtime
// cannot provide. Details/chapters also come from protobuf APIs.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'XOR-encrypted page images + protobuf APIs; requires native byte interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
