// 应用信息：版本号读取与调试信息（对齐 Mihon AboutScreen 点击版本行复制调试信息）
import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';

export class AppInfo {
  private static cached: bundleManager.BundleInfo | undefined = undefined;

  private static bundleInfo(): bundleManager.BundleInfo {
    if (AppInfo.cached === undefined) {
      AppInfo.cached = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    }
    return AppInfo.cached;
  }

  static versionName(): string {
    try {
      const name: string = AppInfo.bundleInfo().versionName;
      return name !== '' ? name : '1.0.0';
    } catch (e) {
      return '1.0.0';
    }
  }

  static versionCode(): number {
    try {
      return AppInfo.bundleInfo().versionCode;
    } catch (e) {
      return 0;
    }
  }

  // 调试信息：版本 + 设备型号 + 系统版本（关于页点击版本行复制到剪贴板）
  static debugInfo(): string {
    const lines: string[] = [
      `Honyomi ${AppInfo.versionName()} (${AppInfo.versionCode()})`,
      `Device: ${deviceInfo.brand} ${deviceInfo.productModel}`,
      `API: ${deviceInfo.sdkApiVersion}`
    ];
    return lines.join('\n');
  }
}
