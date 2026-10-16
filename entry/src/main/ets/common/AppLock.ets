// 应用锁：基于系统锁屏凭据（锁屏口令/人脸/指纹）的用户认证（UserAuthenticationKit）
// 认证由系统统一弹窗完成（安全可控），应用仅收到结果回调，不接触生物特征信息
import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'AppLock';

export class AppLock {
  // 认证成功结果码（ResultCode.SUCCESS）
  private static readonly RESULT_SUCCESS: number = 12500000;

  // 设备是否有可用的解锁凭据（口令/人脸/指纹任一注册即可用）
  // getAvailableStatus：可用时正常返回（void），不可用时抛 BusinessError（未支持/未录入凭据）
  static isAuthSupported(): boolean {
    const types: userAuth.UserAuthType[] = [
      userAuth.UserAuthType.PIN,
      userAuth.UserAuthType.FACE,
      userAuth.UserAuthType.FINGERPRINT
    ];
    for (const t of types) {
      try {
        // 本 SDK 版本 getAvailableStatus 返回 void，不可用时抛出异常：不抛即视为有可用凭据
        userAuth.getAvailableStatus(t, userAuth.AuthTrustLevel.ATL1);
        return true;
      } catch (_e) {
      }
    }
    return false;
  }

  // 拉起系统认证弹窗（title 为弹窗标题，须非空）；认证成功回调 onSuccess，
  // 取消/失败不回调（调用方保持锁定界面，由用户再次触发）
  static authenticate(title: string, onSuccess: () => void): void {
    const challenge: Uint8Array = new Uint8Array(32);
    for (let i = 0; i < challenge.length; i++) {
      challenge[i] = Math.floor(Math.random() * 256);
    }
    const authParam: userAuth.AuthParam = {
      challenge: challenge,
      authType: [
        userAuth.UserAuthType.PIN,
        userAuth.UserAuthType.FACE,
        userAuth.UserAuthType.FINGERPRINT
      ],
      authTrustLevel: userAuth.AuthTrustLevel.ATL1
    };
    const widgetParam: userAuth.WidgetParam = {
      title: title
    };
    try {
      const auth: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      auth.on('result', {
        onResult: (result: userAuth.UserAuthResult): void => {
          try {
            auth.off('result');
          } catch (_e) {
          }
          if (result.result === AppLock.RESULT_SUCCESS) {
            onSuccess();
          }
        }
      });
      auth.start();
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'start auth failed: %{public}d %{public}s', err.code, err.message);
    }
  }
}
