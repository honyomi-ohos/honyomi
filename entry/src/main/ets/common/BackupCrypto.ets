/*
 * BackupCrypto — 备份敏感段加密（PBKDF2 派生密钥 + AES-256-GCM）。
 *
 * 导出：用户密码经 PBKDF2-HMAC-SHA256（100000 轮、16 字节随机盐）派生 32 字节密钥，
 * AES-256-GCM 加密敏感载荷，密文末尾自动追加 16 字节认证 tag。
 * 导入：同参数派生密钥解密；密码错误时 GCM 认证失败抛 backup_bad_password。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

const SALT_BYTES: number = 16;
const GCM_IV_BYTES: number = 12;
const GCM_TAG_BYTES: number = 16;
// PBKDF2 迭代轮数与派生密钥长度（字节）
const PBKDF2_ITERATIONS: number = 100000;
const KEY_BYTES: number = 32;
// 导入侧防滥用上限：拒绝超大迭代数（正常导出恒为 PBKDF2_ITERATIONS）
const MAX_ITERATIONS: number = 10000000;

// 备份文件 secure 段形状（全部 base64 字符串，可 JSON 序列化）
export interface BackupSecureBlob {
  v: number;
  kdf: string;
  iterations: number;
  salt: string;
  iv: string;
  ct: string;
}

export class BackupCrypto {
  static readonly KDF_NAME: string = 'PBKDF2-SHA256';

  /** 明文 JSON 加密为 secure 段；失败抛错（调用方 toast） */
  static async encryptJson(password: string, plain: string): Promise<BackupSecureBlob> {
    if (password === '') {
      throw new Error('backup_password_required');
    }
    const salt: Uint8Array = cryptoFramework.createRandom().generateRandomSync(SALT_BYTES).data;
    const iv: Uint8Array = cryptoFramework.createRandom().generateRandomSync(GCM_IV_BYTES).data;
    const key: cryptoFramework.SymKey = await BackupCrypto.deriveKey(password, salt, PBKDF2_ITERATIONS);
    let cipherText: Uint8Array;
    try {
      const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: new Uint8Array(0) },
        authTag: { data: new Uint8Array(0) },
      };
      cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
      const plainBytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(plain);
      // GCM 加密 doFinal 输出末尾自动追加 16 字节认证 tag
      const out = cipher.doFinalSync({ data: plainBytes });
      cipherText = out.data;
    } catch (e) {
      throw new Error(`backup_encrypt_failed: ${e}`);
    }
    const helper = new util.Base64Helper();
    const blob: BackupSecureBlob = {
      v: 1,
      kdf: BackupCrypto.KDF_NAME,
      iterations: PBKDF2_ITERATIONS,
      salt: helper.encodeToStringSync(salt),
      iv: helper.encodeToStringSync(iv),
      ct: helper.encodeToStringSync(cipherText),
    };
    return blob;
  }

  /**
   * 解密 secure 段；密码错误（GCM 认证失败）抛 Error('backup_bad_password')，
   * 其余失败（格式/参数错误）抛带原因的 Error。
   */
  static async decryptJson(password: string, blob: BackupSecureBlob): Promise<string> {
    if (blob.v !== 1 || blob.kdf !== BackupCrypto.KDF_NAME) {
      throw new Error('backup_secure_unsupported');
    }
    const iterations: number = blob.iterations;
    if (!Number.isFinite(iterations) || iterations <= 0 || iterations > MAX_ITERATIONS) {
      throw new Error('backup_secure_unsupported');
    }
    const helper = new util.Base64Helper();
    let salt: Uint8Array;
    let iv: Uint8Array;
    let ctAll: Uint8Array;
    try {
      salt = helper.decodeSync(blob.salt);
      iv = helper.decodeSync(blob.iv);
      ctAll = helper.decodeSync(blob.ct);
    } catch (e) {
      throw new Error('backup_secure_unsupported');
    }
    if (salt.length === 0 || iv.length === 0 || ctAll.length <= GCM_TAG_BYTES) {
      throw new Error('backup_secure_unsupported');
    }
    const tag: Uint8Array = ctAll.slice(ctAll.length - GCM_TAG_BYTES);
    const cipherText: Uint8Array = ctAll.slice(0, ctAll.length - GCM_TAG_BYTES);
    const key: cryptoFramework.SymKey = await BackupCrypto.deriveKey(password, salt, iterations);
    let plain: Uint8Array;
    try {
      const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: new Uint8Array(0) },
        authTag: { data: tag },
      };
      cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
      // 密码错误时 GCM 认证失败，doFinalSync 抛错
      const out = cipher.doFinalSync({ data: cipherText });
      plain = out.data;
    } catch (e) {
      throw new Error('backup_bad_password');
    }
    return util.TextDecoder.create('utf-8').decodeToString(plain);
  }

  // PBKDF2-HMAC-SHA256 派生 32 字节密钥并转换为 AES256 SymKey
  private static async deriveKey(password: string, salt: Uint8Array,
    iterations: number): Promise<cryptoFramework.SymKey> {
    const kdf = cryptoFramework.createKdf('PBKDF2|SHA256');
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: password,
      salt: salt,
      iterations: iterations,
      keySize: KEY_BYTES,
    };
    let secret: cryptoFramework.DataBlob;
    try {
      secret = await kdf.generateSecret(spec);
    } catch (e) {
      throw new Error(`backup_kdf_failed: ${e}`);
    }
    try {
      const gen = cryptoFramework.createSymKeyGenerator('AES256');
      return gen.convertKeySync({ data: secret.data });
    } catch (e) {
      throw new Error(`backup_kdf_failed: ${e}`);
    }
  }
}
