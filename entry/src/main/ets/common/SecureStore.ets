/*
 * SecureStore — Asset Store Kit（关键资产存储服务）封装。
 *
 * 用于密码 / OAuth token / 插件敏感偏好等短敏感数据的安全存储：
 * 明文在安全环境（TEE）中加密后落 ASSET 数据库，杜绝 preferences 明文落盘。
 *
 * 约束（Asset Store）：SECRET ≤ 1024 字节，ALIAS ≤ 256 字节；
 * 超限时 putSync 返回 false，由调用方回退明文存储（保功能、降安全）。
 * 访问控制：DEVICE_FIRST_UNLOCKED（首次解锁后可访问，支持后台刷新）。
 */
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'SecureStore';

/** Asset 单条 SECRET 的最大字节数 */
export const ASSET_SECRET_MAX_BYTES: number = 1024;

export class SecureStore {
  /** 读取关键资产；不存在或失败返回 '' */
  static getSync(alias: string): string {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, SecureStore.bytes(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const res: Array<asset.AssetMap> = asset.querySync(query);
      if (res.length === 0) {
        return '';
      }
      const secret: asset.Value | undefined = res[0].get(asset.Tag.SECRET);
      if (secret === undefined) {
        return '';
      }
      return util.TextDecoder.create('utf-8').decodeToString(secret as Uint8Array);
    } catch (e) {
      const err = e as BusinessError;
      // 24000002 NOT_FOUND：无该资产，静默返回空
      if (err.code !== 24000002) {
        hilog.warn(DOMAIN, TAG, 'get %{public}s failed: %{public}d', alias, err.code);
      }
      return '';
    }
  }

  /**
   * 写入（upsert）关键资产；secret 为空串时删除该条目。
   * 返回 false 表示不可安全存储（超长 / ASSET 服务失败），调用方应回退明文存储。
   */
  static putSync(alias: string, secret: string): boolean {
    if (secret === '') {
      SecureStore.removeSync(alias);
      return true;
    }
    if (util.TextEncoder.create('utf-8').encodeInto(secret).length > ASSET_SECRET_MAX_BYTES) {
      hilog.warn(DOMAIN, TAG, 'put %{public}s failed: secret exceeds %{public}d bytes', alias,
        ASSET_SECRET_MAX_BYTES);
      return false;
    }
    const attrs: asset.AssetMap = new Map();
    attrs.set(asset.Tag.SECRET, SecureStore.bytes(secret));
    attrs.set(asset.Tag.ALIAS, SecureStore.bytes(alias));
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      asset.addSync(attrs);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'put %{public}s failed: %{public}d', alias, err.code);
      return false;
    }
  }

  /** 删除关键资产；不存在时静默 */
  static removeSync(alias: string): void {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, SecureStore.bytes(alias));
    try {
      asset.removeSync(query);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code !== 24000002) {
        hilog.warn(DOMAIN, TAG, 'remove %{public}s failed: %{public}d', alias, err.code);
      }
    }
  }

  private static bytes(text: string): Uint8Array {
    return util.TextEncoder.create('utf-8').encodeInto(text);
  }
}
