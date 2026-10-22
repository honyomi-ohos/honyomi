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
import { NetworkMonitor } from '../common/NetworkMonitor';

export class BtModule {
  // 会话级实时速率聚合：订阅引擎 1s 进度快照，各任务速率求和写入
  // AppStorage（btDownRate/btUpRate，字节/秒），供设置页 BitTorrent 入口
  // 右侧速率展示；快照停止推送（无活动任务）3.5s 后自动归零防残留末值
  private static rateSubscribed: boolean = false;
  private static rateResetTimer: number = -1;

  // 引擎惰性启动：未启动则启动（downloadDir 为引擎级默认下载目录）。
  // 动态 import 或 start 失败均归一为 bt_component_required：
  // 前者代表组件缺失（走安装引导），后者为引擎初始化异常（极少见，
  // 复用同一引导入口兜底，用户可关闭弹窗后重试）。
  // 会话级限速（设置页可调）在启动时一并下发；分享率限制与 Peer 过滤
  // 规则幂等跟随设置（引擎已启动时确保与设置一致，单条失败下次重试）。
  // 服务总开关默认关闭（应用启动不自动起引擎），触发 BT 下载时自动
  // 打开并按需启动引擎（开关同步为开启，与设置页状态一致）。
  static async ensureStarted(downloadDir: string): Promise<void> {
    try {
      const ns = await import('@honyomi/torrent');
      if (!ns.TorrentManager.isStarted()) {
        await ns.TorrentManager.start(downloadDir, {
          downloadLimit: Settings.getBtDownloadLimitKb() * 1024,
          uploadLimit: BtModule.effectiveUploadLimitBytes()
        });
      }
      if (!BtModule.rateSubscribed) {
        BtModule.rateSubscribed = true;
        ns.TorrentManager.onProgress((statuses: TorrentStatusJson[]): void => {
          BtModule.pushSessionRates(statuses);
        });
      }
      // 触发 BT 下载即启动引擎：同步打开服务总开关（默认关闭，仅代表
      // 「当前引擎开关状态」，不再拦截 BT 下载）
      Settings.setBtServiceEnabled(true);
      // 引擎已启动标志：设置页 BitTorrent 入口右侧速率徽标的可见性
      AppStorage.setOrCreate('btEngineStarted', true);
      ns.TorrentManager.setLimits(Settings.getBtDownloadLimitKb() * 1024,
        BtModule.effectiveUploadLimitBytes())
        .catch((): void => {
        });
      ns.TorrentManager.setShareRatioLimit(Settings.getBtShareRatioLimit())
        .catch((): void => {
        });
      ns.TorrentManager.setIpFilter(BtModule.peerFilterRules())
        .catch((): void => {
        });
    } catch (e) {
      throw new Error('bt_component_required');
    }
  }

  // 手动停引擎（BT 设置总开关关闭时调用）：shutdown 仅停引擎不销毁
  // worker，再次 ensureStarted 可原线程重启；组件缺失/未启动时静默
  static async stopEngine(): Promise<void> {
    try {
      const ns = await import('@honyomi/torrent');
      if (ns.TorrentManager.isStarted()) {
        await ns.TorrentManager.shutdown();
      }
      AppStorage.setOrCreate('btEngineStarted', false);
      BtModule.zeroSessionRates();
    } catch (e) {
      // 组件缺失时无引擎可停
    }
  }

  // 聚合各任务速率写入 AppStorage，并重置归零定时器
  private static pushSessionRates(statuses: TorrentStatusJson[]): void {
    let down = 0;
    let up = 0;
    for (let i = 0; i < statuses.length; i++) {
      down += statuses[i].downloadRate;
      up += statuses[i].uploadRate;
    }
    AppStorage.setOrCreate('btDownRate', down);
    AppStorage.setOrCreate('btUpRate', up);
    if (BtModule.rateResetTimer >= 0) {
      clearTimeout(BtModule.rateResetTimer);
    }
    BtModule.rateResetTimer = setTimeout(() => {
      BtModule.rateResetTimer = -1;
      AppStorage.setOrCreate('btDownRate', 0);
      AppStorage.setOrCreate('btUpRate', 0);
    }, 3500);
  }

  // 速率立即归零并清理挂起的归零定时器
  private static zeroSessionRates(): void {
    if (BtModule.rateResetTimer >= 0) {
      clearTimeout(BtModule.rateResetTimer);
      BtModule.rateResetTimer = -1;
    }
    AppStorage.setOrCreate('btDownRate', 0);
    AppStorage.setOrCreate('btUpRate', 0);
  }

  // 计费网络限制上传（animeko 对齐）：蜂窝/离线时上传压至 10KB/s。
  // OHOS 无 metered 能力位，按"非 Wi-Fi/以太网"判定（fail-open 见 NetworkMonitor）
  static effectiveUploadLimitBytes(): number {
    if (Settings.getBtLimitUploadOnMetered() && !NetworkMonitor.isWifiLike()) {
      return 10 * 1024;
    }
    return Settings.getBtUploadLimitKb() * 1024;
  }

  // Peer 过滤规则：多行文本（每行 "from-to" 区间或单个 IP）→ 字符串数组
  static peerFilterRules(): string[] {
    const raw = Settings.getBtPeerFilter();
    const out: string[] = [];
    if (raw === '') {
      return out;
    }
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (trimmed !== '') {
        out.push(trimmed);
      }
    }
    return out;
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

  // 更新会话级分享率限制（上传/下载比值，达标后停止优先做种）
  static async setShareRatioLimit(ratio: number): Promise<void> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.setShareRatioLimit(ratio);
  }

  // 替换会话级 Peer 过滤规则（每项 "from-to" 或单个 IP；空列表清除过滤）
  static async setIpFilter(rules: string[]): Promise<void> {
    const ns = await import('@honyomi/torrent');
    return ns.TorrentManager.setIpFilter(rules);
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
