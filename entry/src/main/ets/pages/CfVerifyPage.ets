import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Http } from '../net/Http';
import { CookieJar } from '../net/CookieJar';
import { AppIcon, AppIconRes } from './components/AppIcon';

// CF 盾人机验证页：Http 层 / JSVM 插件检测到 challenge 时由 Index 压栈弹出。
// 必须是独立 NavDestination：之前的首页内嵌遮罩会被当前 NavDestination 页盖住，
// 被盖住的 ArkWeb 会暂停加载渲染 —— 弹窗既看不到、网页也白屏，退出浏览页才露出。
// 页面实例持有全新 WebviewController（controller 不可跨 Web 组件复用）；
// Web src 直接指向 challenge URL：onControllerAttached 里同步调 loadUrl 会被
// 引擎随后的初始 src 导航覆盖丢弃（实测只有 about:blank 的 pageBegin/pageEnd）。
// 工具栏对齐 Mihon WebView：页面标题 + 菜单（刷新 / 在浏览器中打开 / 复制链接）+ 完成。
@Component
export struct CfVerifyPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @State cfStatus: ResourceStr = '';
  @State pageTitle: string = '';
  @State loadProgress: number = 0;
  private challengeUrl: string = '';
  // 网页当前地址（跟随重定向更新），供复制/浏览器打开使用
  private currentUrl: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  // 当前主导航是否收到过 4xx/5xx：CF 挑战页本身以 403 下发，其 pageEnd 不代表盾已通过。
  // 防止 aboutToAppear 预注入的旧 cf_clearance 在挑战页首次 pageEnd 时被误判为验证成功。
  private navChallenged: boolean = false;

  aboutToAppear(): void {
    // 触发压栈前 AppStorage.cfChallengeUrl 已写入，此处读取必然非空
    this.challengeUrl = AppStorage.get<string>('cfChallengeUrl') ?? '';
    this.currentUrl = this.challengeUrl;
    this.cfStatus = $r('app.string.tab_cf_waiting');
    hilog.info(0x0C0F, 'CfVerify', 'aboutToAppear url=%{public}s', this.challengeUrl);
    // 把 CookieJar 已有会话预注入 ArkWeb（cf_clearance 与 UA/Cookie 绑定）
    const jar = CookieJar.headerFor(this.challengeUrl);
    if (this.challengeUrl !== '' && jar !== '') {
      webview.WebCookieManager.configCookie(this.challengeUrl, jar).catch((_e: Error) => {
        // 注入失败不阻塞验证
      });
    }
  }

  aboutToDisappear(): void {
    // 任意方式退出（返回键/完成/验证通过）都把 ArkWeb Cookie 回写 CookieJar，
    // 并复位全局触发标记，允许下一次 challenge 重新压栈
    if (this.challengeUrl !== '') {
      webview.WebCookieManager.fetchCookie(this.challengeUrl).then((cookies: string) => {
        CookieJar.importCookieString(this.challengeUrl, cookies);
      }).catch((_e: Error) => {
        // 忽略
      });
    }
    AppStorage.setOrCreate('cfChallengeUrl', '');
  }

  // 每次页面加载完成后检查盾是否通过
  private checkCfSolved(): void {
    if (this.challengeUrl === '') {
      return;
    }
    webview.WebCookieManager.fetchCookie(this.challengeUrl).then((cookies: string) => {
      if (cookies.indexOf('cf_clearance') >= 0) {
        CookieJar.importCookieString(this.challengeUrl, cookies);
        // 通知所有等待验证的插件调用（JsvmSource.call 轮询此计数）携新 cookie 重试
        AppStorage.setOrCreate('cfVerifiedTick', (AppStorage.get<number>('cfVerifiedTick') ?? 0) + 1);
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_verified'));
        this.pathStack.pop();
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
    NavDestination() {
      Column() {
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 22, tint: '#FFFFFF' })
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .onClick(() => {
              this.pathStack.pop();
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
              this.pathStack.pop();
            })
        }
        .width('100%')
        .padding({ top: this.statusBarH })
        .backgroundColor('#CC000000')

        // 页面加载进度条（Mihon WebView 工具栏下方同款细进度条）
        if (this.loadProgress > 0 && this.loadProgress < 100) {
          Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color(this.pal.primary)
            .backgroundColor(this.pal.divider)
        }

        // src 直接指向 challenge URL，让首次导航即目标页；
        // attach 回调早于首次导航 500ms+，setCustomUserAgent 仍赶在首个网络请求前生效
        Web({ src: this.challengeUrl, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .onlineImageAccess(true)
          .onControllerAttached(() => {
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
              this.navChallenged = true;
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
            // 挑战页以 403 下发，其 pageEnd 不算通过；等盾自动/人工通过后的
            // 下一次 200 主导航 pageEnd 再检查 cf_clearance
            const challenged = this.navChallenged;
            this.navChallenged = false;
            if (!challenged) {
              this.checkCfSolved();
            }
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
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
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

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function CfVerifyBuilder() {
  CfVerifyPage()
}
