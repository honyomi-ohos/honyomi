import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Http } from '../net/Http';
import { CookieJar } from '../net/CookieJar';
import { AppIcon } from './components/AppIcon';

// CF 盾人机验证页：Http 层 / JSVM 插件检测到 challenge 时由 Index 压栈弹出。
// 必须是独立 NavDestination：之前的首页内嵌遮罩会被当前 NavDestination 页盖住，
// 被盖住的 ArkWeb 会暂停加载渲染 —— 弹窗既看不到、网页也白屏，退出浏览页才露出。
// 页面实例持有全新 WebviewController（controller 不可跨 Web 组件复用），
// 压栈后立即可见，onControllerAttached → loadUrl 正常执行。
@Component
export struct CfVerifyPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @State cfStatus: ResourceStr = '';
  private challengeUrl: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    // 触发压栈前 AppStorage.cfChallengeUrl 已写入，此处读取必然非空
    this.challengeUrl = AppStorage.get<string>('cfChallengeUrl') ?? '';
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
        Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_verified'));
        this.pathStack.pop();
      }
    }).catch((_e: Error) => {
      // 忽略
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
          Text($r('app.string.tab_cf_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text($r('app.string.tab_cf_done'))
            .fontSize(15)
            .fontColor('#FFFFFF')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .onClick(() => {
              Util.toastRes(this.getUIContext(), $r('app.string.tab_cf_saved'));
              this.pathStack.pop();
            })
        }
        .width('100%')
        .padding({ top: this.statusBarH })
        .backgroundColor('#CC000000')

        // src 直接指向 challenge URL：onControllerAttached 里同步调 loadUrl 会被
        // 引擎随后的初始 src 导航覆盖丢弃（实测 pageBegin/pageEnd 只有 about:blank，
        // 目标 URL 导航从未开始）。让首次导航即目标页，attach 早于首次导航 500ms+，
        // setCustomUserAgent 仍赶在首个网络请求前生效。
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
            hilog.info(0x0C0F, 'CfVerify', 'pageBegin url=%{public}s', event?.url ?? '');
            this.cfStatus = 'Loading…';
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
            hilog.info(0x0C0F, 'CfVerify', 'pageEnd url=%{public}s', event?.url ?? '');
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
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function CfVerifyBuilder() {
  CfVerifyPage()
}
