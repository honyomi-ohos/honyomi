import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { Http } from '../../net/Http';
import { CookieJar } from '../../net/CookieJar';
import { AppIcon, AppIconRes } from './AppIcon';

// CF 盾人机验证半模态弹层（液态玻璃质感，底部弹出）：
// - Index 检测到 challenge 时通过 bindSheet 弹出；弹层位于窗口 popup 层，
//   压在任意 NavDestination（含插件浏览页）之上
// - Web src 直接指向 challenge URL：onControllerAttached 里同步调 loadUrl 会被
//   引擎随后的初始 src 导航覆盖丢弃；attach 早于首次导航，setCustomUserAgent
//   仍赶在首个网络请求前生效
// - controller 每个实例全新创建（不可跨 Web 组件复用）；弹层内容存活期间
//   challenge URL 变化时通过 @Prop @Watch 热切换加载
// - 工具栏对齐 Mihon WebView：页面标题 + 菜单（刷新/在浏览器打开/复制链接）+ 完成
@Component
export struct CfVerifySheet {
  @Prop @Watch('onUrlChanged') challengeUrl: string = '';
  onClose: () => void = () => {};
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State cfStatus: ResourceStr = '';
  @State pageTitle: string = '';
  @State loadProgress: number = 0;
  // 网页当前地址（跟随重定向更新），供复制/浏览器打开使用
  private currentUrl: string = '';
  private loadedUrl: string = '';
  private attached: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.currentUrl = this.challengeUrl;
    this.loadedUrl = this.challengeUrl;
    this.cfStatus = $r('app.string.tab_cf_waiting');
    hilog.info(0x0C0F, 'CfVerify', 'sheet aboutToAppear url=%{public}s', this.challengeUrl);
    // 把 CookieJar 已有会话预注入 ArkWeb（cf_clearance 与 UA/Cookie 绑定）
    const jar = CookieJar.headerFor(this.challengeUrl);
    if (this.challengeUrl !== '' && jar !== '') {
      webview.WebCookieManager.configCookie(this.challengeUrl, jar).catch((_e: Error) => {
        // 注入失败不阻塞验证
      });
    }
  }

  // 弹层内容存活期间 challenge URL 变化（重新触发/换地址）：热切换加载新地址；
  // 若是全新实例则由 Web src 直接指向，无需干预
  private onUrlChanged(): void {
    if (this.challengeUrl === '' || this.challengeUrl === this.loadedUrl || !this.attached) {
      return;
    }
    try {
      this.controller.loadUrl(this.challengeUrl);
      this.currentUrl = this.challengeUrl;
      this.loadedUrl = this.challengeUrl;
      this.cfStatus = $r('app.string.tab_cf_waiting');
    } catch (e) {
      hilog.error(0x0C0F, 'CfVerify', 'hot-switch loadUrl failed: %{public}s',
        (e as BusinessError).message);
    }
  }

  // 每次页面加载完成后检查盾是否通过
  private checkCfSolved(): void {
    if (this.challengeUrl === '') {
      return;
    }
    webview.WebCookieManager.fetchCookie(this.challengeUrl).then((cookies: string) => {
      if (cookies.indexOf('cf_clearance') >= 0) {
        CookieJar.importCookieString(this.challengeUrl, cookies);
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_verified'));
        this.onClose();
      }
    }).catch((_e: Error) => {
      // 忽略
    });
  }

  private refreshPage(): void {
    try {
      this.controller.refresh();
    } catch (e) {
      hilog.error(0x0C0F, 'CfVerify', 'refresh failed: %{public}s', (e as BusinessError).message);
    }
  }

  // 调系统浏览器打开当前页（Mihon WebView 菜单同款操作）
  private openInBrowser(): void {
    const url = this.currentUrl !== '' ? this.currentUrl : this.challengeUrl;
    if (url === '') {
      return;
    }
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const want: Want = { action: 'ohos.want.action.viewData', uri: url };
      context.startAbility(want).catch((e: BusinessError) => {
        hilog.error(0x0C0F, 'CfVerify', 'open in browser failed: %{public}s', e.message);
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_open_failed'));
      });
    } catch (e) {
      hilog.error(0x0C0F, 'CfVerify', 'open in browser failed: %{public}s', (e as BusinessError).message);
      Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_open_failed'));
    }
  }

  // 复制当前页链接到系统剪贴板
  private copyUrl(): void {
    const url = this.currentUrl !== '' ? this.currentUrl : this.challengeUrl;
    if (url === '') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_url_copied'));
    }).catch((_e: Error) => {
      // 复制失败静默
    });
  }

  build() {
    Column() {
      Row() {
        AppIcon({ name: 'close', iconSize: 20, tint: '#FFFFFF' })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .onClick(() => {
            this.onClose();
          })
        Text(this.pageTitle !== '' ? this.pageTitle : $r('app.string.tab_cf_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        AppIcon({ name: 'more_vert', iconSize: 20, tint: '#FFFFFF' })
          .padding({ left: 10, right: 10, top: 12, bottom: 12 })
          .bindMenu(this.cfMenu)
        Text($r('app.string.tab_cf_done'))
          .fontSize(15)
          .fontColor('#FFFFFF')
          .padding({ left: 10, right: 14, top: 10, bottom: 10 })
          .onClick(() => {
            Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_saved'));
            this.onClose();
          })
      }
      .width('100%')
      .backgroundColor('#CC000000')

      // 页面加载进度条（Mihon WebView 工具栏下方同款细进度条）
      if (this.loadProgress > 0 && this.loadProgress < 100) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(this.pal.primary)
          .backgroundColor(this.pal.divider)
      }

      Web({ src: this.challengeUrl, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .onlineImageAccess(true)
        .onControllerAttached(() => {
          this.attached = true;
          hilog.info(0x0C0F, 'CfVerify', 'controller attached, src=%{public}s', this.challengeUrl);
          try {
            // UA 必须在首次加载前设置（cf_clearance 与 UA 绑定）
            this.controller.setCustomUserAgent(Http.USER_AGENT);
            // 主动激活渲染，避免 Web 实例创建后停在未激活状态导致白屏
            this.controller.onActive();
          } catch (e) {
            const err = e as BusinessError;
            hilog.error(0x0C0F, 'CfVerify', 'attach failed: %{public}d %{public}s',
              err.code, err.message);
            this.cfStatus = `Load error: ${err.code} ${err.message}`;
          }
        })
        .onPageBegin((event: OnPageBeginEvent) => {
          this.currentUrl = event?.url ?? this.challengeUrl;
          hilog.info(0x0C0F, 'CfVerify', 'pageBegin url=%{public}s', this.currentUrl);
          this.cfStatus = 'Loading…';
        })
        .onTitleReceive((event: OnTitleReceiveEvent) => {
          this.pageTitle = event?.title ?? '';
        })
        .onProgressChange((event: OnProgressChangeEvent) => {
          this.loadProgress = event?.newProgress ?? 0;
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          // 主文档加载失败时回显原因，避免无声白屏
          if (event && event.request.isMainFrame()) {
            hilog.error(0x0C0F, 'CfVerify', 'errorReceive(main) url=%{public}s info=%{public}s',
              event.request.getRequestUrl(), event.error.getErrorInfo());
            this.cfStatus = `Load failed: ${event.error.getErrorInfo()}`;
          }
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          if (event && event.request.isMainFrame()) {
            hilog.info(0x0C0F, 'CfVerify', 'httpError(main) url=%{public}s code=%{public}d %{public}s',
              event.request.getRequestUrl(), event.response.getResponseCode(),
              event.response.getReasonMessage());
            this.cfStatus = `HTTP ${event.response.getResponseCode()}`;
          }
        })
        .onRenderExited((event: OnRenderExitedEvent) => {
          hilog.error(0x0C0F, 'CfVerify', 'renderExited reason=%{public}d', event?.renderExitReason ?? -1);
          if (event) {
            this.cfStatus = `Render exited (${event.renderExitReason})`;
          }
        })
        .onPageEnd((event: OnPageEndEvent) => {
          this.currentUrl = event?.url ?? this.currentUrl;
          hilog.info(0x0C0F, 'CfVerify', 'pageEnd url=%{public}s', this.currentUrl);
          this.checkCfSolved();
        })
        .layoutWeight(1)

      Text(this.cfStatus)
        .fontSize(12)
        .fontColor(this.pal.sub)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(8)
    }
    .width('100%')
    .height('100%')
  }

  // 工具栏菜单：刷新 / 在浏览器中打开 / 复制链接（对齐 Mihon WebView 菜单）
  @Builder
  cfMenu() {
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
