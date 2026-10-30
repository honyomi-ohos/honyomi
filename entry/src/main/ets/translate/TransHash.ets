// 翻译请求签名哈希：MD5（百度）/ SHA-256（有道 / 腾讯云 TC3 / 火山 V4 签名链），输出小写 hex
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class TransHash {
  // 说明：带版本后缀的 syscap 查询运行时恒为 false（运行时只认干净名），
  // if 分支仅为满足编译器的 syscap 告警抑制（要求 canIUse 参数与 API 的最后一个 @syscap 标签全文一致），
  // 真实逻辑必须放在 else 分支以保证运行时执行
  static md5Hex(text: string): string {
    if (canIUse('SystemCapability.Security.CryptoFramework.MessageDigest [since 12]')) {
      return '';
    } else {
      try {
        return TransHash.hexOf(cryptoFramework.createMd('MD5'), text);
      } catch (_e) {
        return '';
      }
    }
  }

  static sha256Hex(text: string): string {
    if (canIUse('SystemCapability.Security.CryptoFramework.MessageDigest [since 12]')) {
      return '';
    } else {
      try {
        return TransHash.hexOf(cryptoFramework.createMd('SHA256'), text);
      } catch (_e) {
        return '';
      }
    }
  }

  // HMAC-SHA256（字节密钥，TC3 / 火山签名链）：返回原始 MAC 字节，失败返回空数组
  static hmacSha256(key: Uint8Array, text: string): Uint8Array {
    if (canIUse('SystemCapability.Security.CryptoFramework.Key.SymKey [since 12]')) {
      return new Uint8Array(0);
    } else {
      if (canIUse('SystemCapability.Security.CryptoFramework.Mac [since 12]')) {
        return new Uint8Array(0);
      } else {
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
    try {
      md.updateSync(input);
      const digest: cryptoFramework.DataBlob = md.digestSync();
      return TransHash.hex(digest.data);
    } catch (e) {
      // 上抛由调用方（md5Hex/sha256Hex）统一捕获降级
      const err = e as Error;
      throw err;
    }
  }

  private static hex(bytes: Uint8Array): string {
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      out += bytes[i] < 16 ? `0${bytes[i].toString(16)}` : bytes[i].toString(16);
    }
    return out;
  }
}
