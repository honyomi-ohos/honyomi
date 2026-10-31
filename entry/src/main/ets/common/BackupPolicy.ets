import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'BackupPolicy';

// 备份策略注册表：@NoBackup/@NoBackupPrefix/@Sensitive 装饰器在类定义（模块加载）时
// 将策略写入本表，Settings 导出/导入据此过滤。策略声明在设置访问器上（声明处即登记），
// 不再维护集中式排除清单。
export class BackupPolicyRegistry {
  private static readonly excludedKeys: string[] = [];
  private static readonly excludedPrefixes: string[] = [];
  private static readonly sensitiveKeys: string[] = [];

  static excludeKey(key: string): void {
    if (BackupPolicyRegistry.excludedKeys.indexOf(key) < 0) {
      BackupPolicyRegistry.excludedKeys.push(key);
    }
  }

  static excludePrefix(prefix: string): void {
    if (BackupPolicyRegistry.excludedPrefixes.indexOf(prefix) < 0) {
      BackupPolicyRegistry.excludedPrefixes.push(prefix);
    }
  }

  static markSensitive(key: string): void {
    if (BackupPolicyRegistry.sensitiveKeys.indexOf(key) < 0) {
      BackupPolicyRegistry.sensitiveKeys.push(key);
    }
  }

  // 键是否被排除出备份（精确键或前缀族）
  static isExcluded(key: string): boolean {
    if (BackupPolicyRegistry.excludedKeys.indexOf(key) >= 0) {
      return true;
    }
    for (const prefix of BackupPolicyRegistry.excludedPrefixes) {
      if (key.indexOf(prefix) === 0) {
        return true;
      }
    }
    return false;
  }

  // 键是否为敏感设置（进加密 secure 段，不进明文段）
  static isSensitive(key: string): boolean {
    return BackupPolicyRegistry.sensitiveKeys.indexOf(key) >= 0;
  }

  static sensitiveKeyList(): string[] {
    return BackupPolicyRegistry.sensitiveKeys.slice();
  }

  // 金丝雀：装饰器是否已生效（trustedPlugins 的排除登记必须存在）。
  // 若装饰器被编译器丢弃（理论不可达），导出/导入整体 fail-closed，
  // 宁可备份缺设置段，也不导出插件信任状态或敏感键明文。
  static decoratorsApplied(): boolean {
    return BackupPolicyRegistry.excludedKeys.indexOf('trustedPlugins') >= 0;
  }
}

// 装饰器：该设置键不进备份（易变状态/设备本地数据/安全敏感记录）
export function NoBackup(key: string): (target: Object, propKey: string, descriptor: Object) => void {
  return (target: Object, propKey: string, descriptor: Object): void => {
    BackupPolicyRegistry.excludeKey(key);
    hilog.debug(0x0000, TAG, 'no-backup: %{public}s', key);
  };
}

// 装饰器：该前缀族键不进备份（按 id 动态拼键的设备本地数据）
export function NoBackupPrefix(prefix: string): (target: Object, propKey: string, descriptor: Object) => void {
  return (target: Object, propKey: string, descriptor: Object): void => {
    BackupPolicyRegistry.excludePrefix(prefix);
    hilog.debug(0x0000, TAG, 'no-backup-prefix: %{public}s', prefix);
  };
}

// 装饰器：该设置键为敏感凭据，仅进加密 secure 段，不进明文段
export function Sensitive(key: string): (target: Object, propKey: string, descriptor: Object) => void {
  return (target: Object, propKey: string, descriptor: Object): void => {
    BackupPolicyRegistry.markSensitive(key);
    hilog.debug(0x0000, TAG, 'sensitive: %{public}s', key);
  };
}
