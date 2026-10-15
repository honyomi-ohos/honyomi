// OAuth 授权 WebView 弹层（bindSheet 半模态承载）：
// - 各追踪器授权完成后统一重定向 mihon://<tracker>-auth，携带 query 或 fragment 参数
// - onLoadIntercept 拦截 mihon:// 跳转并解析参数，回传发起方完成登录
// - 对齐 Mihon TrackLoginActivity：query 优先，缺失时取 fragment
// - 网页明暗跟随应用：darkMode(On/Off) 让适配深色的站点按 prefers-color-scheme 渲染，
//   forceDarkAccess 强制未适配的站点反转配色（应用深色时两者同时开启）
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Http } from '../../net/Http';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { AppIcon } from './AppIcon';

const MIHON_SCHEME: string = 'mihon://';

@Component
export struct OAuthSheet {
  @Prop authUrl: string = '';
  @Prop sheetTitle: Resource | string = '';
  // 拦截到 mihon:// 回调后回传参数（query 优先，缺失取 fragment）
  onOAuthResult: (params: Record<string, string>) => void = (_p: Record<string, string>) => {};
  onClose: () => void = () => {};
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State loadProgress: number = 0;
  @State statusText: ResourceStr = '';
  private handled: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  // 解析 mihon://host?query 或 mihon://host#fragment 中的键值对
  static parseParams(url: string): Record<string, string> {
    const params: Record<string, string> = {};
    const queryIdx = url.indexOf('?');
    const hashIdx = url.indexOf('#');
    let data = '';
    if (queryIdx >= 0) {
      const end = hashIdx > queryIdx ? hashIdx : url.length;
      data = url.substring(queryIdx + 1, end);
    } else if (hashIdx >= 0) {
      data = url.substring(hashIdx + 1);
    }
    if (data !== '') {
      const pairs = data.split('&');
      const seen = new Set<string>();
      for (const pair of pairs) {
        if (pair === '') {
          continue;
        }
        const eq = pair.indexOf('=');
        if (eq <= 0) {
          continue;
        }
        const key = decodeURIComponent(pair.substring(0, eq));
        const value = decodeURIComponent(pair.substring(eq + 1));
        if (!seen.has(key)) {
          seen.add(key);
          params[key] = value;
        }
      }
    }
    return params;
  }

  private tryHandleRedirect(url: string): boolean {
    if (this.handled || !url.startsWith(MIHON_SCHEME)) {
      return false;
    }
    this.handled = true;
    hilog.info(0x0C0F, 'OAuth', 'redirect intercepted: %{public}s', url);
    this.onOAuthResult(OAuthSheet.parseParams(url));
    return true;
  }

  build() {
    Column() {
      Row() {
        AppIcon({ name: 'close', iconSize: 20, tint: this.pal.text })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .onClick(() => {
            this.onClose();
          })
        Text(this.sheetTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .backgroundColor(this.pal.bg)

      if (this.loadProgress > 0 && this.loadProgress < 100) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(this.pal.primary)
          .backgroundColor(this.pal.divider)
      }

      Web({ src: this.authUrl, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .onlineImageAccess(true)
        .darkMode(this.isDark ? WebDarkMode.On : WebDarkMode.Off)
        .forceDarkAccess(this.isDark)
        .onControllerAttached(() => {
          try {
            this.controller.setCustomUserAgent(Http.USER_AGENT);
            this.controller.onActive();
          } catch (e) {
            const err = e as BusinessError;
            hilog.error(0x0C0F, 'OAuth', 'attach failed: %{public}d %{public}s', err.code, err.message);
          }
        })
        .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
          return this.tryHandleRedirect(event.data.getRequestUrl());
        })
        .onPageBegin((event: OnPageBeginEvent) => {
          // 兜底：部分引擎 onLoadIntercept 不含 fragment 时由 onPageBegin 捕获
          this.tryHandleRedirect(event?.url ?? '');
          this.statusText = $r('app.string.oauth_loading');
        })
        .onProgressChange((event: OnProgressChangeEvent) => {
          this.loadProgress = event?.newProgress ?? 0;
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          if (event && event.request.isMainFrame() && !this.handled) {
            hilog.warn(0x0C0F, 'OAuth', 'errorReceive(main): %{public}s', event.error.getErrorInfo());
            this.statusText = Util.resStr(this.getUIContext(), $r('app.string.oauth_load_error'),
              [event.error.getErrorInfo()]);
          }
        })
        .onRenderExited((event: OnRenderExitedEvent) => {
          hilog.error(0x0C0F, 'OAuth', 'renderExited reason=%{public}d', event?.renderExitReason ?? -1);
        })
        .layoutWeight(1)

      if (this.statusText !== '') {
        Text(this.statusText)
          .fontSize(12)
          .fontColor(this.pal.sub)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(8)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }
}
