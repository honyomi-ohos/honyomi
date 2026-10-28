// 翻译请求签名哈希：MD5（百度）/ SHA-256（有道），输出小写 hex
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class TransHash {
  static md5Hex(text: string): string {
    try {
      return TransHash.hexOf(cryptoFramework.createMd('MD5'), text);
    } catch (_e) {
      return '';
    }
  }

  static sha256Hex(text: string): string {
    try {
      return TransHash.hexOf(cryptoFramework.createMd('SHA256'), text);
    } catch (_e) {
      return '';
    }
  }

  private static hexOf(md: cryptoFramework.Md, text: string): string {
    const encoder = new util.TextEncoder();
    const input: cryptoFramework.DataBlob = { data: encoder.encodeInto(text) };
    md.updateSync(input);
    const digest: cryptoFramework.DataBlob = md.digestSync();
    return TransHash.hex(digest.data);
  }

  private static hex(bytes: Uint8Array): string {
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      out += bytes[i] < 16 ? `0${bytes[i].toString(16)}` : bytes[i].toString(16);
    }
    return out;
  }
}
