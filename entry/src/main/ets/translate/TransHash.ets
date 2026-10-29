// 翻译请求签名哈希：MD5（百度）/ SHA-256（有道 / 腾讯云 TC3 / 火山 V4 签名链），输出小写 hex
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

  // HMAC-SHA256（字节密钥，TC3 / 火山签名链）：返回原始 MAC 字节，失败返回空数组
  static hmacSha256(key: Uint8Array, text: string): Uint8Array {
    try {
      const encoder = new util.TextEncoder();
      const generator = cryptoFramework.createSymKeyGenerator('HMAC');
      const symKey = generator.convertKeySync({ data: key });
      const mac = cryptoFramework.createMac('SHA256');
      mac.initSync(symKey);
      mac.updateSync({ data: encoder.encodeInto(text) });
      return mac.doFinalSync().data;
    } catch (_e) {
      return new Uint8Array(0);
    }
  }

  // HMAC-SHA256（字符串密钥）→ 小写 hex（腾讯 TC3 首级 kDate、NiuTrans 等直接签名场景）
  static hmacSha256Hex(key: string, text: string): string {
    const encoder = new util.TextEncoder();
    return TransHash.hex(TransHash.hmacSha256(encoder.encodeInto(key), text));
  }

  // 字节数组 → 小写 hex（签名链末级 Signature 输出用）
  static toHex(bytes: Uint8Array): string {
    return TransHash.hex(bytes);
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
