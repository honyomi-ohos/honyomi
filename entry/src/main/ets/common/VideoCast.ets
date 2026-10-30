import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'VideoCast';

// 投屏媒体信息（仅支持网络直链，页面构造后交给远端设备拉流播放）
export interface VideoCastItem {
  assetId: string;
  title: string;
  artist: string;
  mediaUri: string;
  startPosition: number;
  duration: number;
}

// 投屏会话元数据（播控中心展示）
export interface VideoCastMeta {
  assetId: string;
  title: string;
  artist: string;
}

// 投屏事件回调（页面实现：连接/断开/远端播放态/播放结束/播控中心命令）
export interface VideoCastEvents {
  onConnected: (deviceName: string) => void;
  onDisconnected: (positionMs: number) => void;
  onPlayback: (playing: boolean, positionMs: number, durationMs: number) => void;
  onEnded: () => void;
  onCommand: (command: string) => void;
}

// 视频投屏封装（参考投播开发指导）：AVSession 声明投播能力（requireAbilityList），
// 设备发现连接由系统 AVCastPicker 完成，连接成功后经 AVCastController 下发资源与播控命令
export class VideoCastManager {
  private session: avSession.AVSession | undefined = undefined;
  private controller: avSession.AVCastController | undefined = undefined;
  private events: VideoCastEvents;
  private connected: boolean = false;
  private lastPosMs: number = 0;
  private settingUp: boolean = false;

  constructor(events: VideoCastEvents) {
    this.events = events;
  }

  isActive(): boolean {
    return this.connected;
  }

  // 创建（或复用）video 会话并刷新元数据；picker 弹出前必须先完成本调用
  async ensureSession(context: common.UIAbilityContext, meta: VideoCastMeta): Promise<boolean> {
    this.settingUp = true;
    try {
      if (this.session === undefined) {
        const s: avSession.AVSession = await avSession.createAVSession(context, 'video_cast', 'video');
        this.session = s;
        await s.activate();
        // 告知系统当前应用支持投播，否则 picker 设备列表为空
        await s.setExtras({ requireAbilityList: ['url-cast'] });
        this.bindSession(s);
      }
      const md: avSession.AVMetadata = {
        assetId: meta.assetId,
        title: meta.title,
        artist: meta.artist,
        // 发现 Cast+ Stream 与 DLNA 协议设备
        filter: avSession.ProtocolType.TYPE_CAST_PLUS_STREAM | avSession.ProtocolType.TYPE_DLNA
      };
      await this.session.setAVMetadata(md);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'ensureSession failed: %{public}d %{public}s', err.code, `${e}`);
      return false;
    } finally {
      this.settingUp = false;
    }
  }

  // 下发投屏资源（prepare 成功后 start 真正起播）
  startCast(item: VideoCastItem): void {
    const ctrl = this.controller;
    if (ctrl === undefined) {
      hilog.warn(DOMAIN, TAG, 'startCast without controller');
      return;
    }
    const desc: avSession.AVMediaDescription = {
      assetId: item.assetId,
      title: item.title,
      artist: item.artist,
      mediaUri: item.mediaUri,
      mediaType: 'VIDEO',
      startPosition: Math.floor(item.startPosition),
      duration: item.duration > 0 ? Math.floor(item.duration) : 0
    };
    const queueItem: avSession.AVQueueItem = { itemId: 0, description: desc };
    ctrl.prepare(queueItem).then((): void => {
      const c = this.controller;
      if (c === undefined) {
        return;
      }
      c.start(queueItem).catch((e: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'cast start failed: %{public}d %{public}s', e.code, e.message);
      });
    }).catch((e: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'cast prepare failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  // 远端播放/暂停（play 为 true 表示下发播放命令）
  sendPlay(play: boolean): void {
    this.sendCommand(play ? 'play' : 'pause');
  }

  // 远端进度调节（毫秒）
  seek(ms: number): void {
    const ctrl = this.controller;
    if (ctrl === undefined) {
      return;
    }
    const cmd: avSession.AVCastControlCommand = { command: 'seek', parameter: Math.floor(ms) };
    ctrl.sendControlCommand(cmd).catch((e: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'cast seek failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  // 主动断开投播（断开事件仍经 onDisconnected 回调通知页面）
  stopCasting(): void {
    const s = this.session;
    if (s === undefined) {
      return;
    }
    s.stopCasting().catch((e: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'stopCasting failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  // 销毁会话（播放页退出时调用；若在投屏中会先断开）
  destroy(): void {
    const s = this.session;
    this.cleanupController();
    this.session = undefined;
    if (s === undefined) {
      return;
    }
    try {
      s.off('outputDeviceChange');
      s.off('play');
      s.off('pause');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'session off failed: %{public}s', `${e}`);
    }
    s.destroy().catch((e: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'session destroy failed: %{public}d %{public}s', e.code, e.message);
    });
  }

  private bindSession(s: avSession.AVSession): void {
    try {
      s.on('outputDeviceChange', (connectState: avSession.ConnectionState,
        device: avSession.OutputDeviceInfo) => {
        this.onDeviceChange(connectState, device);
      });
      s.on('play', (): void => {
        this.events.onCommand('play');
      });
      s.on('pause', (): void => {
        this.events.onCommand('pause');
      });
    } catch (e) {
      // 上抛由 ensureSession 统一捕获（保持既有失败路径）
const err = e as Error;
      throw err;
    }
  }

  private async onDeviceChange(connectState: avSession.ConnectionState,
    device: avSession.OutputDeviceInfo): Promise<void> {
    const devices: avSession.DeviceInfo[] = device !== undefined && device.devices !== undefined ?
      device.devices : [];
    const remote: avSession.DeviceInfo | undefined = devices.length > 0 ? devices[0] : undefined;
    if (connectState === avSession.ConnectionState.STATE_CONNECTED &&
      remote !== undefined && remote.castCategory === avSession.AVCastCategory.CATEGORY_REMOTE) {
      if (this.controller !== undefined) {
        return;
      }
      const s = this.session;
      if (s === undefined) {
        return;
      }
      try {
        const ctrl: avSession.AVCastController = await s.getAVCastController();
        this.controller = ctrl;
        this.connected = true;
        this.lastPosMs = 0;
        ctrl.on('playbackStateChange', 'all', (state: avSession.AVPlaybackState) => {
          this.onPlaybackState(state);
        });
        ctrl.on('endOfStream', (): void => {
          this.events.onEnded();
        });
        hilog.info(DOMAIN, TAG, 'cast connected: %{public}s', remote.deviceName);
        this.events.onConnected(remote.deviceName);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'getAVCastController failed: %{public}s', `${e}`);
      }
      return;
    }
    if (connectState === avSession.ConnectionState.STATE_DISCONNECTED && this.connected) {
      const pos: number = this.lastPosMs;
      this.cleanupController();
      hilog.info(DOMAIN, TAG, 'cast disconnected, lastPos=%{public}d', pos);
      this.events.onDisconnected(pos);
    }
  }

  private onPlaybackState(state: avSession.AVPlaybackState): void {
    const pos: avSession.PlaybackPosition | undefined = state.position;
    if (pos !== undefined && pos.elapsedTime >= 0) {
      this.lastPosMs = pos.elapsedTime;
    }
    const playing: boolean = state.state === avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    const dur: number = state.duration !== undefined ? state.duration : 0;
    this.events.onPlayback(playing, this.lastPosMs, dur);
  }

  private cleanupController(): void {
    const ctrl = this.controller;
    this.controller = undefined;
    this.connected = false;
    if (ctrl !== undefined) {
      try {
        ctrl.off('playbackStateChange');
        ctrl.off('endOfStream');
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'controller off failed: %{public}s', `${e}`);
      }
    }
  }

  private sendCommand(command: avSession.AVCastControlCommandType): void {
    const ctrl = this.controller;
    if (ctrl === undefined) {
      return;
    }
    const cmd: avSession.AVCastControlCommand = { command: command };
    ctrl.sendControlCommand(cmd).catch((e: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'cast cmd %{public}s failed: %{public}d %{public}s', command, e.code, e.message);
    });
  }
}
