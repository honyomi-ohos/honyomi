import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { Http } from '../../net/Http';
import { CookieJar } from '../../net/CookieJar';
import { AppIcon, AppIconRes } from './AppIcon';

// 在线插件站点预览半模态弹层（安装前查看插件对应网站的交互与设计）：
// - 工具栏/菜单/进度条与 CfVerifySheet（Mihon WebView）保持一致：
//   Chrome 风格加载图标 + 页面标题 + 菜单（刷新/在浏览器打开/复制链接）+ 关闭
// - 预注入 CookieJar 已有会话（如站点要求登录，预览可复用插件抓取会话）
// - controller 每实例全新创建；Web 延迟一拍挂载避免引擎初始化阻塞工具栏首帧
@Component
export struct SitePreviewSheet {
  @Prop siteUrl: string = '';
  // 默认标题（插件名）：页面标题未收到前显示
  @Prop defaultTitle: string = '';
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State loadProgress: number = 0;
  // Chrome 风格加载态：标题前图标切换（加载中转圈 / 加载完成地球）
  @State loading: boolean = true;
  @State pageTitle: string = '';
  // 与工具栏同帧挂载会导致 Image 图标（close 等）解码上屏被阻塞而延迟显示
  @State webMounted: boolean = false;
  // Web 延迟挂载：引擎初始化（拉起渲染进程）会抢占 UI 线程，
  // 网页当前地址（跟随重定向更新），供复制/浏览器打开使用
  private currentUrl: string = '';
  // 弹层内容销毁标志：异步续体据此跳过 toast/写状态
  private disposed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  // Web 延迟挂载定时器：销毁时清理，防回调写已销毁组件状态
  private mountTimerId: number = -1;
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    this.currentUrl = this.siteUrl;
    // 把 CookieJar 已有会话预注入 ArkWeb（插件抓取会话与站点 Cookie 同域复用）
    const jar = CookieJar.headerFor(this.siteUrl);
    if (this.siteUrl !== '' && jar !== '') {
      webview.WebCookieManager.configCookie(this.siteUrl, jar).catch((_e: BusinessError) => {
        // 注入失败不阻塞预览
      });
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
        Text(this.pageTitle !== '' ? this.pageTitle :
          (this.defaultTitle !== '' ? this.defaultTitle : $r('app.string.plugin_site_preview_title')))
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
          .bindMenu(this.siteMenu)
      }
      .width('100%')

      // 页面加载进度条（Mihon WebView 工具栏下方同款细进度条）
      if (this.loadProgress > 0 && this.loadProgress < 100) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(this.pal.primary)
          .backgroundColor(this.pal.divider)
      }

      if (this.webMounted) {
        Web({ src: this.siteUrl, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .onlineImageAccess(true)
          .darkMode(this.isDark ? WebDarkMode.On : WebDarkMode.Off)
          .forceDarkAccess(this.isDark)
          .onControllerAttached(() => {
            try {
              this.controller.setCustomUserAgent(Http.USER_AGENT);
              // 主动激活渲染，避免 Web 实例创建后停在未激活状态导致白屏
              this.controller.onActive();
            } catch (e) {
              const err = e as BusinessError;
              hilog.error(0x0C0F, 'SitePreview', 'attach failed: %{public}d %{public}s',
                err.code, err.message);
            }
          })
          .onPageBegin((event: OnPageBeginEvent) => {
            this.currentUrl = event?.url ?? this.siteUrl;
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
              hilog.error(0x0C0F, 'SitePreview', 'errorReceive(main) host=%{public}s info=%{public}s',
                CookieJar.hostOf(event.request.getRequestUrl()), event.error.getErrorInfo());
              this.loading = false;
            }
          })
          .onRenderExited((event: OnRenderExitedEvent) => {
            hilog.error(0x0C0F, 'SitePreview', 'renderExited reason=%{public}d', event?.renderExitReason ?? -1);
          })
          .onPageEnd((event: OnPageEndEvent) => {
            this.currentUrl = event?.url ?? this.currentUrl;
            this.loading = false;
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
  siteMenu() {
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

  private refreshPage(): void {
    try {
      this.controller.refresh();
    } catch (e) {
      hilog.error(0x0C0F, 'SitePreview', 'refresh failed: %{public}s', (e as BusinessError).message);
    }
  }

  // 调系统浏览器打开当前页（Mihon WebView 菜单同款操作）
  private openInBrowser(): void {
    const url = this.currentUrl !== '' ? this.currentUrl : this.siteUrl;
    if (url === '') {
      return;
    }
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const want: Want = { action: 'ohos.want.action.viewData', uri: url };
      context.startAbility(want).catch((e: BusinessError) => {
        hilog.error(0x0C0F, 'SitePreview', 'open in browser failed: %{public}s', e.message);
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_open_failed'));
      });
    } catch (e) {
      hilog.error(0x0C0F, 'SitePreview', 'open in browser failed: %{public}s', (e as BusinessError).message);
      Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_open_failed'));
    }
  }

  // 工具栏菜单：刷新 / 在浏览器中打开 / 复制链接（对齐 Mihon WebView 菜单）

  // 复制当前页链接到系统剪贴板
  private copyUrl(): void {
    const url = this.currentUrl !== '' ? this.currentUrl : this.siteUrl;
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
