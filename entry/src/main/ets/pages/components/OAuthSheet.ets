// OAuth 授权 WebView 弹层（bindSheet 半模态承载，工具栏/菜单样式与 CfVerifySheet 保持一致）：
// - 各追踪器授权完成后统一重定向 mihon://<tracker>-auth，携带 query 或 fragment 参数
// - onLoadIntercept 拦截 mihon:// 跳转并解析参数，回传发起方完成登录
// - 对齐 Mihon TrackLoginActivity：query 优先，缺失时取 fragment
// - 网页明暗跟随应用：darkMode(On/Off) 让适配深色的站点按 prefers-color-scheme 渲染，
//   forceDarkAccess 强制未适配的站点反转配色（应用深色时两者同时开启）
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { Http } from '../../net/Http';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { AppIcon, AppIconRes } from './AppIcon';

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
  // Chrome 风格加载态：标题前图标切换（加载中转圈 / 加载完成地球）
  @State loading: boolean = true;
  @State pageTitle: string = '';
  private handled: boolean = false;
  // 网页当前地址（跟随重定向更新），供复制/浏览器打开使用
  private currentUrl: string = '';
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

  private refreshPage(): void {
    try {
      this.controller.refresh();
    } catch (e) {
      hilog.error(0x0C0F, 'OAuth', 'refresh failed: %{public}s', (e as BusinessError).message);
    }
  }

  // 调系统浏览器打开当前页（与 CfVerifySheet 菜单同款操作）
  private openInBrowser(): void {
    const url = this.currentUrl !== '' ? this.currentUrl : this.authUrl;
    if (url === '') {
      return;
    }
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const want: Want = { action: 'ohos.want.action.viewData', uri: url };
      context.startAbility(want).catch((e: BusinessError) => {
        hilog.error(0x0C0F, 'OAuth', 'open in browser failed: %{public}s', e.message);
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_open_failed'));
      });
    } catch (e) {
      hilog.error(0x0C0F, 'OAuth', 'open in browser failed: %{public}s', (e as BusinessError).message);
      Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_open_failed'));
    }
  }

  // 复制当前页链接到系统剪贴板
  private copyUrl(): void {
    const url = this.currentUrl !== '' ? this.currentUrl : this.authUrl;
    if (url === '') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_url_copied'));
    }).catch((_e: BusinessError) => {
      // 复制失败静默
    });
  }

  build() {
    Column() {
      Row() {
        AppIcon({ name: 'close', iconSize: 20, tint: this.pal.text })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .onClick(() => {
            this.onClose();
          })
        if (this.loading) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.pal.primary)
        } else {
          AppIcon({ name: 'public', iconSize: 16, tint: this.pal.sub })
        }
        Text(this.pageTitle !== '' ? this.pageTitle : this.sheetTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 6 })
        AppIcon({ name: 'more_vert', iconSize: 20, tint: this.pal.text })
          .padding({ left: 10, right: 10, top: 12, bottom: 12 })
          .bindMenu(this.oauthMenu)
      }
      .width('100%')

      // 页面加载进度条（与 CfVerifySheet 工具栏下方同款细进度条）
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
          this.currentUrl = event?.url ?? this.authUrl;
          // 兜底：部分引擎 onLoadIntercept 不含 fragment 时由 onPageBegin 捕获
          this.tryHandleRedirect(this.currentUrl);
          this.loading = true;
        })
        .onTitleReceive((event: OnTitleReceiveEvent) => {
          this.pageTitle = event?.title ?? '';
        })
        .onProgressChange((event: OnProgressChangeEvent) => {
          this.loadProgress = event?.newProgress ?? 0;
        })
        .onPageEnd((event: OnPageEndEvent) => {
          this.currentUrl = event?.url ?? this.currentUrl;
          this.loading = false;
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          if (event && event.request.isMainFrame() && !this.handled) {
            hilog.warn(0x0C0F, 'OAuth', 'errorReceive(main): %{public}s', event.error.getErrorInfo());
            this.loading = false;
          }
        })
        .onRenderExited((event: OnRenderExitedEvent) => {
          hilog.error(0x0C0F, 'OAuth', 'renderExited reason=%{public}d', event?.renderExitReason ?? -1);
        })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  // 工具栏菜单：刷新 / 在浏览器中打开 / 复制链接（与 CfVerifySheet 菜单同款）
  // 菜单图标经 dark 资源限定符适配明暗（base 黑色 / dark 白色），避免深色菜单下不可见
  @Builder
  oauthMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.tab_cf_refresh'), startIcon: AppIconRes.get('refresh') })
        .onClick(() => {
          this.refreshPage();
        })
      MenuItem({ content: $r('app.string.tab_cf_open_browser'), startIcon: AppIconRes.get('open_in_new') })
        .onClick(() => {
          this.openInBrowser();
        })
      MenuItem({ content: $r('app.string.tab_cf_copy_url'), startIcon: AppIconRes.get('content_copy') })
        .onClick(() => {
          this.copyUrl();
        })
    }
  }
}
