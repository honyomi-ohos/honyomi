import { WebViewSheetBase } from './WebViewSheetBase';

// 在线插件站点预览半模态弹层（骨架由 WebViewSheetBase 承载，安装前查看插件对应网站）：
// - 工具栏/菜单/进度条与 CfVerifySheet（Mihon WebView）保持一致
// - 预注入 CookieJar 已有会话（如站点要求登录，预览可复用插件抓取会话）
// - 页面标题未收到前显示插件名，均缺失时显示默认标题
@Component
export struct SitePreviewSheet {
  @Prop siteUrl: string = '';
  // 默认标题（插件名）：页面标题未收到前显示
  @Prop defaultTitle: string = '';
  onClose: () => void = () => {
  };

  build() {
    WebViewSheetBase({
      targetUrl: this.siteUrl,
      titleFallback: this.defaultTitle !== '' ? this.defaultTitle : $r('app.string.plugin_site_preview_title'),
      logTag: 'SitePreview',
      injectCookies: true,
      onClose: (): void => {
        this.onClose();
      }
    })
  }
}
