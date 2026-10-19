/*
 * BtModule — BT 引擎（torrent 集成态 HSP）按需加载门面。
 *
 * torrent 模块经 AppGallery 按需分发（deliveryWithInstall:false），首次安装
 * 应用时不随主包下发；DownloadService 走 BT 下载前先经 BtComponentInstaller
 * 确认组件已安装，再动态 import 加载。各方法独立发起动态 import：ArkTS 运
 * 时对同一说明符的模块加载有缓存，重复调用无额外开销。
 *
 * 组件缺失（未安装/被卸载）时动态 import 被拒绝，ensureStarted 统一归一为
 * bt_component_required 错误码，由 DownloadService.process 捕获后置前台安
 * 装引导标志（Index 的 BtComponentDialog 消费）。
 */
import type { TorrentStatusJson } from '@honyomi/torrent';

export class BtModule {
  // 引擎惰性启动：未启动则启动（downloadDir 为引擎级默认下载目录）。
  // 动态 import 或 start 失败均归一为 bt_component_required：
  // 前者代表组件缺失（走安装引导），后者为引擎初始化异常（极少见，
  // 复用同一引导入口兜底，用户可关闭弹窗后重试）
  static async ensureStarted(downloadDir: string): Promise<void> {
    try {
      const ns = await import('@honyomi/torrent');
      if (!ns.TorrentManager.isStarted()) {
        await ns.TorrentManager.start(downloadDir);
      }
    } catch (e) {
      throw new Error('bt_component_required');
    }
  }

  static async addMagnet(magnetUri: string, savePath: string): Promise<number> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.addMagnet(magnetUri, savePath);
  }

  static async addTorrentFile(bytes: Uint8Array, savePath: string): Promise<number> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.addTorrentFile(bytes, savePath);
  }

  static async status(key: number): Promise<TorrentStatusJson> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.status(key);
  }

  static async remove(key: number, deleteFiles: boolean): Promise<void> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.remove(key, deleteFiles);
  }
}
