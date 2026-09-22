// ja/zerosumonline — Zero Sum Online ( 一迅社 )
// Honest skip: the API returns binary protobuf messages (TitleListView/TitleDetailView/
// ViewerView). The JS plugin runtime's HTTP layer is text-only and has no protobuf decoder.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'Binary protobuf API responses; runtime HTTP layer is text-only with no proto decoder (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
