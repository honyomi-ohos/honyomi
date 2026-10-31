import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { CookieJar } from '../../net/CookieJar';
import { AppKeys } from '../../common/AppKeys';
import { Util } from '../../common/Util';
import { WebViewSheetBase } from './WebViewSheetBase';

// CF 盾人机验证半模态弹层（骨架由 WebViewSheetBase 承载）：
// - Index 检测到 challenge 时通过 bindSheet 弹出；弹层位于窗口 popup 层，
//   压在任意 NavDestination（含插件浏览页）之上
// - 预注入 CookieJar 已有会话（cf_clearance 与 UA/Cookie 绑定）；challenge URL
//   变化时经骨架 @Watch 热切换加载
// - 每次页面加载完成后检查是否下发了「新的」cf_clearance（值 ≠ 弹层打开时的旧值，
//   对齐 Mihon CloudflareInterceptor 的 oldCookie 比对）：预注入的旧 clearance
//   若只判存在会立即误判通过 → 验证弹层无限循环；导入 CookieJar、广播验证计数、
//   toast 并关闭弹层
@Component
export struct CfVerifySheet {
  @Prop challengeUrl: string = '';
  // 弹层内容销毁标志：异步回调（fetchCookie 等）续体据此跳过 toast/onClose
  private disposed: boolean = false;
  // 弹层打开时该域已有的 cf_clearance 旧值（空 = 无旧会话）
  private oldClearance: string = '';
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    this.oldClearance = CookieJar.getCookie(this.challengeUrl, 'cf_clearance');
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  build() {
    WebViewSheetBase({
      targetUrl: this.challengeUrl,
      titleFallback: $r('app.string.tab_cf_title'),
      logTag: 'CfVerify',
      injectCookies: true,
      showDone: true,
      onClose: (): void => {
        this.onClose();
      },
      onPageEnded: (_url: string): void => {
        this.checkCfSolved();
      }
    })
  }

  // 从 cookie 字符串（"a=1; cf_clearance=x; b=2"）提取 cf_clearance 值
  private static clearanceValue(cookieStr: string): string {
    const parts = cookieStr.split(';');
    for (const part of parts) {
      const p = part.trim();
      if (p.indexOf('cf_clearance=') === 0) {
        return p.substring('cf_clearance='.length).trim();
      }
    }
    return '';
  }

  // 每次页面加载完成后检查盾是否通过（拿到与旧值不同的新 cf_clearance）
  private checkCfSolved(): void {
    if (this.challengeUrl === '') {
      return;
    }
    webview.WebCookieManager.fetchCookie(this.challengeUrl).then((cookies: string) => {
      const fresh = CfVerifySheet.clearanceValue(cookies);
      if (fresh !== '' && fresh !== this.oldClearance) {
        CookieJar.importCookieString(this.challengeUrl, cookies);
        // 通知等待 CF 验证结果的插件请求重试（JsvmSource 轮询此计数器）
        AppStorage.setOrCreate(AppKeys.CF_VERIFIED_TICK,
          (AppStorage.get<number>(AppKeys.CF_VERIFIED_TICK) ?? 0) + 1);
        if (this.disposed) {
          return;
        }
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_verified'));
        this.onClose();
      }
    }).catch((_e: BusinessError) => {
      // 忽略
    });
  }
}
