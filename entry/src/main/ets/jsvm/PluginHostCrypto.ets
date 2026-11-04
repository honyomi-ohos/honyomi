/*
 * PluginHostCrypto — 插件 HostCalls 用的 AES（CBC / GCM / CTR）。
 * 一律走 @kit.CryptoArchitectureKit，与 BackupCrypto / HlsDownloader 同栈。
 * 载荷均为原始字节；GCM 密文约定 ct||tag（tag 16 字节），与现有 $.crypto 一致。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const CRYPTO_BYTES_MAX: number = 64 * 1024 * 1024;
const GCM_TAG_BYTES: number = 16;
const GCM_IV_BYTES: number = 12;
const CBC_IV_BYTES: number = 16;
const CTR_IV_BYTES: number = 16;

export class PluginHostCrypto {
  static aesCbc(data: Uint8Array, key: Uint8Array, iv: Uint8Array, decrypt: boolean): Uint8Array {
    PluginHostCrypto.requireLen('aes', data, 1, CRYPTO_BYTES_MAX);
    PluginHostCrypto.requireAesKey('aes', key);
    const iv16 = PluginHostCrypto.padIv(iv, CBC_IV_BYTES);
    const alg = PluginHostCrypto.aesAlg(key.length);
    // CBC：PKCS7，对齐现有 $.crypto.aesCbcDecrypt 填充约定
    const cipher = cryptoFramework.createCipher(`${alg}|CBC|PKCS7`);
    const params: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: iv16 },
    };
    cipher.initSync(
      decrypt ? cryptoFramework.CryptoMode.DECRYPT_MODE : cryptoFramework.CryptoMode.ENCRYPT_MODE,
      PluginHostCrypto.symKey(alg, key),
      params,
    );
    try {
      const out = cipher.doFinalSync({ data: data });
      return out.data;
    } catch (e) {
      throw new Error(`aes: ${PluginHostCrypto.err(e)}`);
    }
  }

  static aesGcm(data: Uint8Array, key: Uint8Array, iv: Uint8Array, aad: Uint8Array, decrypt: boolean): Uint8Array {
    PluginHostCrypto.requireAesKey('aes-gcm', key);
    if (iv.length !== GCM_IV_BYTES) {
      throw new Error(`aes-gcm: nonce length must be 12, got ${iv.length}`);
    }
    const alg = PluginHostCrypto.aesAlg(key.length);
    if (decrypt) {
      PluginHostCrypto.requireLen('aes-gcm', data, GCM_TAG_BYTES + 1, CRYPTO_BYTES_MAX);
      const tag = data.slice(data.length - GCM_TAG_BYTES);
      const ct = data.slice(0, data.length - GCM_TAG_BYTES);
      const cipher = cryptoFramework.createCipher(`${alg}|GCM|NoPadding`);
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: aad },
        authTag: { data: tag },
      };
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, PluginHostCrypto.symKey(alg, key), params);
      try {
        const out = cipher.doFinalSync({ data: ct });
        return out.data;
      } catch (e) {
        throw new Error(`aes-gcm: ${PluginHostCrypto.err(e)}`);
      }
    }
    PluginHostCrypto.requireLen('aes-gcm', data, 0, CRYPTO_BYTES_MAX);
    const cipher = cryptoFramework.createCipher(`${alg}|GCM|NoPadding`);
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: aad },
      authTag: { data: new Uint8Array(0) },
    };
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, PluginHostCrypto.symKey(alg, key), params);
    try {
      // doFinal 输出末尾自动追加 16 字节 tag → ct||tag
      const out = cipher.doFinalSync({ data: data });
      return out.data;
    } catch (e) {
      throw new Error(`aes-gcm: ${PluginHostCrypto.err(e)}`);
    }
  }

  static aesCtr(data: Uint8Array, key: Uint8Array, iv: Uint8Array, decrypt: boolean): Uint8Array {
    PluginHostCrypto.requireLen('aes-ctr', data, 0, CRYPTO_BYTES_MAX);
    PluginHostCrypto.requireAesKey('aes-ctr', key);
    if (iv.length !== CTR_IV_BYTES) {
      throw new Error(`aes-ctr: iv length must be 16, got ${iv.length}`);
    }
    const alg = PluginHostCrypto.aesAlg(key.length);
    // CTR / NoPadding：与 Kotlin AES/CTR/NoPadding 对齐；加解密同函数
    const cipher = cryptoFramework.createCipher(`${alg}|CTR|NoPadding`);
    const params: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: iv },
    };
    cipher.initSync(
      decrypt ? cryptoFramework.CryptoMode.DECRYPT_MODE : cryptoFramework.CryptoMode.ENCRYPT_MODE,
      PluginHostCrypto.symKey(alg, key),
      params,
    );
    try {
      const out = cipher.doFinalSync({ data: data });
      return out.data;
    } catch (e) {
      throw new Error(`aes-ctr: ${PluginHostCrypto.err(e)}`);
    }
  }

  private static aesAlg(keyLen: number): string {
    if (keyLen === 16) {
      return 'AES128';
    }
    if (keyLen === 24) {
      return 'AES192';
    }
    return 'AES256';
  }

  private static symKey(alg: string, key: Uint8Array): cryptoFramework.SymKey {
    const gen = cryptoFramework.createSymKeyGenerator(alg);
    return gen.convertKeySync({ data: key });
  }

  private static requireAesKey(prefix: string, key: Uint8Array): void {
    if (key.length !== 16 && key.length !== 24 && key.length !== 32) {
      throw new Error(`${prefix}: key length must be 16, 24, or 32, got ${key.length}`);
    }
  }

  private static requireLen(prefix: string, data: Uint8Array, min: number, max: number): void {
    if (data.length < min || data.length > max) {
      throw new Error(`${prefix}: data length ${data.length} out of range ${min}..${max}`);
    }
  }

  private static padIv(iv: Uint8Array, size: number): Uint8Array {
    if (iv.length >= size) {
      return iv.slice(0, size);
    }
    const out = new Uint8Array(size);
    out.set(iv);
    return out;
  }

  private static err(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }
}
