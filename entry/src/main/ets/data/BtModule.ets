/*
 * BtModule — BT 引擎（torrent 集成态 HSP）按需加载门面。
 *
 * torrent 模块经 AppGallery 按需分发（deliveryWithInstall:false），首次安装
 * 应用时不随主包下发；DownloadService 走 BT 下载前先经 BtComponentInstaller
 * 确认组件已安装，再动态 import 加载。各方法独立发起动态 import：ArkTS 运
 * 行时对同一说明符的模块加载有缓存，重复调用无额外开销。
 *
 * 组件缺失（未安装/被卸载）时动态 import 被拒绝，ensureStarted 统一归一为
 * bt_component_required 错误码，由 DownloadService.process 捕获后置前台安
 * 装引导标志（Index 的 BtComponentDialog 消费）。
 */
import type { TorrentFileJson, TorrentStatusJson } from '@honyomi/torrent';
import { Settings } from '../common/Settings';

export class BtModule {
  // 引擎惰性启动：未启动则启动（downloadDir 为引擎级默认下载目录）。
  // 动态 import 或 start 失败均归一为 bt_component_required：
  // 前者代表组件缺失（走安装引导），后者为引擎初始化异常（极少见，
  // 复用同一引导入口兜底，用户可关闭弹窗后重试）。
  // 会话级限速（设置页可调）在启动时一并下发。
  static async ensureStarted(downloadDir: string): Promise<void> {
    try {
      const ns = await import('@honyomi/torrent');
      if (!ns.TorrentManager.isStarted()) {
        await ns.TorrentManager.start(downloadDir, {
          downloadLimit: Settings.getBtDownloadLimitKb() * 1024,
          uploadLimit: Settings.getBtUploadLimitKb() * 1024
        });
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

  // 向任务追加额外 tracker（native 侧对已有 URL 去重），返回实际新增数
  static async addTrackers(key: number, trackers: string[]): Promise<number> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.addTrackers(key, trackers);
  }

  // 顺序下载（边下边播友好：优先完成文件头部，播放器可提前起播）
  static async setSequential(key: number, enabled: boolean): Promise<void> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.setSequential(key, enabled);
  }

  // 文件级进度（metadata 就绪前为空数组；边下边播起播门槛判定用）
  static async files(key: number): Promise<TorrentFileJson[]> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.files(key);
  }

  // 更新会话级限速（字节/秒，0 = 不限）；设置页调整时即时生效
  static async setLimits(downloadLimit: number, uploadLimit: number): Promise<void> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.setLimits(downloadLimit, uploadLimit);
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
