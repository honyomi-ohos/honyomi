import { common } from '@kit.AbilityKit';
import { HashMap } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CacheListener, HeaderInjector, HttpProxyCacheServer, HttpProxyCacheServerBuilder } from '@ohos/video-cache';
import { Http } from '../net/Http';

// 按 URL 附加源站请求头的注入器：播放前经 VideoCacheServer.setUrlHeaders 注册
// 各直链所需头（Referer 等），代理服务器向源站发起下载时再合并 UA/Cookie
class RegisteredHeaderInjector implements HeaderInjector {
  addHeaders(url: string): HashMap<string, string> {
    const out: HashMap<string, string> = new HashMap<string, string>();
    const merged: Record<string, string> = Http.headersFor(url, VideoCacheServer.getUrlHeaders(url));
    const keys = Object.keys(merged);
    for (const k of keys) {
      try {
        out.set(k, merged[k]);
      } catch (_e) {
      }
    }
    return out;
  }
}

// 视频代理缓存服务（参考 openharmony-tpc OhosVideoCache 示例）：
// 单例 HttpProxyCacheServer 边下边播，快进/回退命中本地缓存即刻起播；
// HLS(m3u8) 为多文件流媒体，不支持单文件代理缓存，走直连播放
export class VideoCacheServer {
  private static server: HttpProxyCacheServer | undefined = undefined;
  private static urlHeaders: Map<string, Record<string, string>> = new Map<string, Record<string, string>>();

  // 是否可走代理缓存：HTTP/HTTPS 直链且非 m3u8
  static isProxyEligible(url: string): boolean {
    return url.indexOf('http') === 0 && url.indexOf('.m3u8') < 0;
  }

  static setUrlHeaders(url: string, headers: Record<string, string>): void {
    VideoCacheServer.urlHeaders.set(url, headers);
  }

  static getUrlHeaders(url: string): Record<string, string> | undefined {
    return VideoCacheServer.urlHeaders.get(url);
  }

  // 获取代理播放地址；已完整缓存时返回本地缓存文件路径
  static async getProxyUrl(context: common.UIAbilityContext, url: string,
    headers: Record<string, string>): Promise<string> {
    if (VideoCacheServer.server === undefined) {
      VideoCacheServer.server = new HttpProxyCacheServerBuilder(context)
        .cacheDirectory(`${context.cacheDir}/video_cache`)
        .maxCacheSize(512 * 1024 * 1024)
        .setHeaderInjector(new RegisteredHeaderInjector())
        .build();
    }
    VideoCacheServer.setUrlHeaders(url, headers);
    const proxyUrl: string = await VideoCacheServer.server.getProxyUrl(url);
    hilog.info(0xDEAD, 'VideoCache', 'getProxyUrl origin=%s -> %{public}s', url, proxyUrl);
    return proxyUrl;
  }

  static registerCacheListener(listener: CacheListener, url: string): void {
    if (VideoCacheServer.server !== undefined) {
      VideoCacheServer.server.registerCacheListener(listener, url);
    }
  }

  static unregisterCacheListener(listener: CacheListener, url: string): void {
    if (VideoCacheServer.server !== undefined) {
      VideoCacheServer.server.unregisterCacheListener(listener, url);
    }
  }
}
