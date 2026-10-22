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
// - 每次页面加载完成后检查 cf_clearance 是否下发：导入 CookieJar、广播验证计数、
//   toast 并关闭弹层
@Component
export struct CfVerifySheet {
  @Prop challengeUrl: string = '';
  // 弹层内容销毁标志：异步回调（fetchCookie 等）续体据此跳过 toast/onClose
  private disposed: boolean = false;
  onClose: () => void = () => {
  };

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

  // 每次页面加载完成后检查盾是否通过
  private checkCfSolved(): void {
    if (this.challengeUrl === '') {
      return;
    }
    webview.WebCookieManager.fetchCookie(this.challengeUrl).then((cookies: string) => {
      if (cookies.indexOf('cf_clearance') >= 0) {
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
