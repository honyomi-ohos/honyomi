import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'NetworkMonitor';

// 网络环境监听：供下载服务实现"仅 Wi-Fi 下载"的网络侧判定。
// Wi-Fi / 以太网视为可下载环境；完全离线或蜂窝网络时阻断新任务。
// 任何探测失败（无权限/接口异常）一律放行，避免误杀正常下载（fail-open）。
export class NetworkMonitor {
  private static wifiLike: boolean = true;
  private static started: boolean = false;

  static isWifiLike(): boolean {
    return NetworkMonitor.wifiLike;
  }

  // onChange：网络环境判定结果发生变化时回调（如 false→true 时恢复下载队列）
  static start(onChange: () => void): void {
    if (NetworkMonitor.started) {
      return;
    }
    NetworkMonitor.started = true;
    NetworkMonitor.check(onChange);
    try {
      const conn = connection.createNetConnection();
      conn.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo): void => {
        // SDK 中 NetCapabilityInfo 的能力字段名为 netCap（非 netCapabilities）
        NetworkMonitor.applyCaps(info.netCap, onChange);
      });
      conn.on('netUnavailable', (): void => {
        // 网络完全断开：复检（getDefaultNet 失败时 fail-open 由 check 兜底）
        NetworkMonitor.check(onChange);
      });
      conn.register((error: BusinessError): void => {
        if (error) {
          hilog.warn(0x0001, TAG, 'register net connection failed: %{public}s', error.message);
        }
      });
    } catch (e) {
      hilog.warn(0x0001, TAG, 'create net connection failed: %{public}s', `${e}`);
    }
  }

  // 主动复检当前默认网络（启动时/网络变化事件兜底）
  private static check(onChange: () => void): void {
    connection.getDefaultNet().then((handle: connection.NetHandle): Promise<connection.NetCapabilities> => {
      return connection.getNetCapabilities(handle);
    }).then((caps: connection.NetCapabilities): void => {
      NetworkMonitor.applyCaps(caps, onChange);
    }).catch((_e: BusinessError): void => {
      hilog.warn(0x0001, TAG, 'detect network failed, fail-open');
      NetworkMonitor.applyFlag(true, onChange);
    });
  }

  private static applyCaps(caps: connection.NetCapabilities, onChange: () => void): void {
    let wifiLike = false;
    if (caps !== undefined && Array.isArray(caps.bearerTypes)) {
      for (const t of caps.bearerTypes) {
        if (t === connection.NetBearType.BEARER_WIFI || t === connection.NetBearType.BEARER_ETHERNET) {
          wifiLike = true;
          break;
        }
      }
    }
    NetworkMonitor.applyFlag(wifiLike, onChange);
  }

  private static applyFlag(wifiLike: boolean, onChange: () => void): void {
    if (wifiLike !== NetworkMonitor.wifiLike) {
      NetworkMonitor.wifiLike = wifiLike;
      onChange();
    }
  }
}
