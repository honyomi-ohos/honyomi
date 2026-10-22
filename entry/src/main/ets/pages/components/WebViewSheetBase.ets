import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { Http } from '../../net/Http';
import { CookieJar } from '../../net/CookieJar';
import { AppIcon, AppIconRes } from './AppIcon';

// 通用 WebView 弹层骨架：CfVerifySheet / OAuthSheet / SitePreviewSheet 共用，收敛约 60-70% 重复结构。
// - 工具栏：Chrome 风格加载图标 + 页面标题（未收到时显示兜底标题）+ 菜单（刷新/浏览器打开/复制链接）
//   + 可选「完成」按钮（showDone）
// - 可选防钓鱼域名条（showHostLine）：常驻展示当前域名，非 https 以警示色标出
// - Web 事件接线：attach 时设 UA 并激活渲染；标题/进度/错误回调；目标地址热切换（@Watch）
// - CookieJar 会话预注入（injectCookies）；Web 延迟一拍挂载，销毁清理定时器
// - 刷新 / 在浏览器打开 / 复制链接菜单操作与异步 toast 的 disposed 防护
// 差异行为经钩子回调注入（onInterceptLoad/onPageBegun/onPageEnded/onClose）。
// 注意：controller 每个实例全新创建（不可跨 Web 组件复用）；onControllerAttached 里同步调
// loadUrl 会被引擎随后的初始 src 导航覆盖丢弃；attach 早于首次导航，setCustomUserAgent
// 仍赶在首个网络请求前生效。
@Component
export struct WebViewSheetBase {
  // Web src 与复制/浏览器打开的兜底地址；弹层存活期间变化时热切换加载新地址
  @Prop @Watch('onTargetUrlChanged') targetUrl: string = '';
  // 页面标题未收到前显示的兜底标题
  @Prop titleFallback: Resource | string = '';
  // 日志 tag（区分 CfVerify/OAuth/SitePreview）
  logTag: string = 'WebViewSheet';
  // true = aboutToAppear 时把 CookieJar 已有会话预注入 ArkWeb（cf_clearance 与 UA/Cookie 绑定）
  injectCookies: boolean = false;
  // true = 工具栏尾部显示「完成」按钮（点击 toast + onClose）
  showDone: boolean = false;
  // true = 工具栏下方常驻展示当前页域名/协议（非 https 警示色，防钓鱼）
  showHostLine: boolean = false;
  // 弹层关闭回调
  onClose: () => void = () => {
  };
  // onLoadIntercept 钩子：返回 true 表示该次导航已消费（OAuth 拦截 mihon:// 回调用）
  onInterceptLoad: (url: string) => boolean = (_url: string) => false;
  // 页面开始/结束导航钩子（携带当前地址；OAuth fragment 兜底拦截、CF 通过检查等用）
  onPageBegun: (url: string) => void = (_url: string) => {
  };
  onPageEnded: (url: string) => void = (_url: string) => {
  };

  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State loadProgress: number = 0;
  // Chrome 风格加载态：标题前图标切换（加载中转圈 / 加载完成地球）
  @State loading: boolean = true;
  @State pageTitle: string = '';
  // 防钓鱼：当前页面域名与协议（非 https 时以警示色展示）
  @State pageHost: string = '';
  @State pageSecure: boolean = true;
  // 与工具栏同帧挂载会导致 Image 图标（close 等）解码上屏被阻塞而延迟显示
  @State webMounted: boolean = false;
  // 网页当前地址（跟随重定向更新），供复制/浏览器打开使用
  private currentUrl: string = '';
  private loadedUrl: string = '';
  private attached: boolean = false;
  // 弹层内容销毁标志：异步续体据此跳过 toast/写状态
  private disposed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  // Web 延迟挂载定时器：销毁时清理，防回调写已销毁组件状态
  private mountTimerId: number = -1;

  aboutToAppear(): void {
    this.currentUrl = this.targetUrl;
    this.loadedUrl = this.targetUrl;
    this.updateHost(this.targetUrl);
    // URL 偶含会话参数：日志只输出 host，不输出完整 URL
    hilog.info(0x0C0F, this.logTag, 'sheet aboutToAppear host=%{public}s', CookieJar.hostOf(this.targetUrl));
    if (this.injectCookies) {
      const jar = CookieJar.headerFor(this.targetUrl);
      if (this.targetUrl !== '' && jar !== '') {
        webview.WebCookieManager.configCookie(this.targetUrl, jar).catch((_e: BusinessError) => {
          // 注入失败不阻塞
        });
      }
    }
    // 延迟一拍挂载 Web，让工具栏（含图标）首帧先绘制上屏
    this.mountTimerId = setTimeout(() => {
      this.mountTimerId = -1;
      this.webMounted = true;
    }, 100);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.mountTimerId >= 0) {
      clearTimeout(this.mountTimerId);
      this.mountTimerId = -1;
    }
  }

  build() {
    Column() {
      Row() {
        AppIcon({ name: 'close', iconSize: 20, tint: this.pal.text })
          .padding({
            left: 14,
            right: 14,
            top: 10,
            bottom: 10
          })
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
        Text(this.pageTitle !== '' ? this.pageTitle : this.titleFallback)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 6 })
        AppIcon({ name: 'more_vert', iconSize: 20, tint: this.pal.text })
          .padding({
            left: 10,
            right: 10,
            top: 12,
            bottom: 12
          })
          .bindMenu(this.sheetMenu)
        if (this.showDone) {
          Text($r('app.string.tab_cf_done'))
            .fontSize(15)
            .fontColor(this.pal.primary)
            .padding({
              left: 10,
              right: 14,
              top: 10,
              bottom: 10
            })
            .onClick(() => {
              Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_saved'));
              this.onClose();
            })
        }
      }
      .width('100%')

      // 防钓鱼：常驻展示当前域名；非 https 连接以警示色标出
      if (this.showHostLine) {
        Text(this.pageHost === '' ? ' ' : this.pageHost)
          .fontSize(11)
          .fontColor(this.pageSecure ? this.pal.sub : '#B45309')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 3, bottom: 3 })
      }

      // 页面加载进度条（Mihon WebView 工具栏下方同款细进度条）
      if (this.loadProgress > 0 && this.loadProgress < 100) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(this.pal.primary)
          .backgroundColor(this.pal.divider)
      }

      if (this.webMounted) {
        Web({ src: this.targetUrl, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .onlineImageAccess(true)
          .darkMode(this.isDark ? WebDarkMode.On : WebDarkMode.Off)
          .forceDarkAccess(this.isDark)
          .onControllerAttached(() => {
            this.attached = true;
            hilog.info(0x0C0F, this.logTag, 'controller attached, src=%{public}s', this.targetUrl);
            try {
              // UA 必须在首次加载前设置（cf_clearance 与 UA 绑定）
              this.controller.setCustomUserAgent(Http.USER_AGENT);
              // 主动激活渲染，避免 Web 实例创建后停在未激活状态导致白屏
              this.controller.onActive();
            } catch (e) {
              const err = e as BusinessError;
              hilog.error(0x0C0F, this.logTag, 'attach failed: %{public}d %{public}s', err.code, err.message);
            }
          })
          .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
            return this.onInterceptLoad(event.data.getRequestUrl());
          })
          .onPageBegin((event: OnPageBeginEvent) => {
            this.currentUrl = event?.url ?? this.targetUrl;
            this.updateHost(this.currentUrl);
            hilog.info(0x0C0F, this.logTag, 'pageBegin host=%{public}s', CookieJar.hostOf(this.currentUrl));
            this.onPageBegun(this.currentUrl);
            this.loading = true;
          })
          .onTitleReceive((event: OnTitleReceiveEvent) => {
            this.pageTitle = event?.title ?? '';
          })
          .onProgressChange((event: OnProgressChangeEvent) => {
            this.loadProgress = event?.newProgress ?? 0;
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            // 主文档加载失败时记录原因（页面由引擎默认错误页呈现）；只输出 host，不输出完整 URL
            if (event && event.request.isMainFrame()) {
              hilog.error(0x0C0F, this.logTag, 'errorReceive(main) host=%{public}s info=%{public}s',
                CookieJar.hostOf(event.request.getRequestUrl()), event.error.getErrorInfo());
              this.loading = false;
            }
          })
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
            if (event && event.request.isMainFrame()) {
              hilog.info(0x0C0F, this.logTag, 'httpError(main) host=%{public}s code=%{public}d %{public}s',
                CookieJar.hostOf(event.request.getRequestUrl()), event.response.getResponseCode(),
                event.response.getReasonMessage());
            }
          })
          .onRenderExited((event: OnRenderExitedEvent) => {
            hilog.error(0x0C0F, this.logTag, 'renderExited reason=%{public}d', event?.renderExitReason ?? -1);
          })
          .onPageEnd((event: OnPageEndEvent) => {
            this.currentUrl = event?.url ?? this.currentUrl;
            this.updateHost(this.currentUrl);
            hilog.info(0x0C0F, this.logTag, 'pageEnd host=%{public}s', CookieJar.hostOf(this.currentUrl));
            this.loading = false;
            this.onPageEnded(this.currentUrl);
          })
          .layoutWeight(1)
      } else {
        // Web 未挂载时的占位，保持布局稳定
        Column()
          .width('100%')
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }

  // 菜单图标经 dark 资源限定符适配明暗（base 黑色 / dark 白色），避免深色菜单下不可见
  @Builder
  sheetMenu() {
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

  // 弹层内容存活期间目标地址变化（重新触发/换地址）：热切换加载新地址；
  // 若是全新实例则由 Web src 直接指向，无需干预
  private onTargetUrlChanged(): void {
    if (this.targetUrl === '' || this.targetUrl === this.loadedUrl || !this.attached) {
      return;
    }
    try {
      this.controller.loadUrl(this.targetUrl);
      this.currentUrl = this.targetUrl;
      this.loadedUrl = this.targetUrl;
      this.loading = true;
    } catch (e) {
      hilog.error(0x0C0F, this.logTag, 'hot-switch loadUrl failed: %{public}s', (e as BusinessError).message);
    }
  }

  // 更新当前页面域名/协议展示（授权中域名变化即刷新，防钓鱼）
  private updateHost(url: string): void {
    this.pageHost = CookieJar.hostOf(url);
    this.pageSecure = url.indexOf('https://') === 0;
  }

  private refreshPage(): void {
    try {
      this.controller.refresh();
    } catch (e) {
      hilog.error(0x0C0F, this.logTag, 'refresh failed: %{public}s', (e as BusinessError).message);
    }
  }

  // 调系统浏览器打开当前页（Mihon WebView 菜单同款操作）
  private openInBrowser(): void {
    const url = this.currentUrl !== '' ? this.currentUrl : this.targetUrl;
    if (url === '') {
      return;
    }
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const want: Want = { action: 'ohos.want.action.viewData', uri: url };
      context.startAbility(want).catch((e: BusinessError) => {
        hilog.error(0x0C0F, this.logTag, 'open in browser failed: %{public}s', e.message);
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_open_failed'));
      });
    } catch (e) {
      hilog.error(0x0C0F, this.logTag, 'open in browser failed: %{public}s', (e as BusinessError).message);
      Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_open_failed'));
    }
  }

  // 复制当前页链接到系统剪贴板
  private copyUrl(): void {
    const url = this.currentUrl !== '' ? this.currentUrl : this.targetUrl;
    if (url === '') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      if (!this.disposed) {
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_url_copied'));
      }
    }).catch((_e: BusinessError) => {
      // 复制失败静默
    });
  }
}
