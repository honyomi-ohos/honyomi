// OAuth 授权 WebView 弹层（bindSheet 半模态承载，骨架由 WebViewSheetBase 承载）：
// - 各追踪器授权完成后统一重定向自定义 scheme 回调（mihon://<tracker>-auth 或
//   honyomi://<tracker>-auth），携带 query 或 fragment 参数
// - onLoadIntercept 钩子拦截回调跳转并解析参数，回传发起方完成登录；
//   部分引擎 onLoadIntercept 不含 fragment 时由 onPageBegun 钩子兜底捕获
// - 对齐 Mihon TrackLoginActivity：query 优先，缺失时取 fragment
// - 防钓鱼域名条常驻展示（骨架 showHostLine）
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebViewSheetBase } from './WebViewSheetBase';

// 迁移期双 scheme：未换凭据的追踪器仍回调 mihon://，已注册新凭据的回调 honyomi://
const CALLBACK_SCHEMES: string[] = ['mihon://', 'honyomi://'];

@Component
export struct OAuthSheet {
  @Prop authUrl: string = '';
  @Prop sheetTitle: Resource | string = '';
  private handled: boolean = false;

  // 解析 scheme://host?query 或 scheme://host#fragment 中的键值对
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

  // 拦截到 scheme 回调后回传参数（query 优先，缺失取 fragment）
  onOAuthResult: (params: Record<string, string>) => void = (_p: Record<string, string>) => {
  };

  onClose: () => void = () => {
  };

  build() {
    WebViewSheetBase({
      targetUrl: this.authUrl,
      titleFallback: this.sheetTitle,
      logTag: 'OAuth',
      showHostLine: true,
      onClose: (): void => {
        this.onClose();
      },
      onInterceptLoad: (url: string): boolean => {
        return this.tryHandleRedirect(url);
      },
      onPageBegun: (url: string): void => {
        // 兜底：部分引擎 onLoadIntercept 不含 fragment 时由 onPageBegin 捕获
        this.tryHandleRedirect(url);
      }
    })
  }

  private tryHandleRedirect(url: string): boolean {
    if (this.handled) {
      return false;
    }
    let matched: string = '';
    for (const scheme of CALLBACK_SCHEMES) {
      if (url.startsWith(scheme)) {
        matched = scheme;
        break;
      }
    }
    if (matched === '') {
      return false;
    }
    this.handled = true;
    // 回调 URL 的 query/fragment 携带 access_token：只记录回调标识（host），绝不输出完整 URL
    const host = url.substring(matched.length).split('?')[0].split('#')[0].split('/')[0];
    hilog.info(0x0C0F, 'OAuth', 'redirect intercepted: %{public}s', host);
    this.onOAuthResult(OAuthSheet.parseParams(url));
    return true;
  }
}
