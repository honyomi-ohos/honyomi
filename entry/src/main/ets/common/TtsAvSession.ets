import { avSession } from '@kit.AVSessionKit';
import { common, wantAgent } from '@kit.AbilityKit';
import type { WantAgent } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'TtsAvSession';

// 听书播控会话元数据（播控中心/锁屏媒体卡片展示）
export interface TtsSessionMeta {
  assetId: string;
  title: string; // 章节名
  artist: string; // 作者
  queueName: string; // 书名
  queueId: string;
  coverUri: string; // 本地封面（file:// 开头），空串表示无
}

// 播控中心/锁屏媒体控制命令
export interface TtsSessionCommands {
  onPlay: () => void;
  onPause: () => void;
  onNext: () => void;
  onPrev: () => void;
}

// 小说听书 AVSession 封装（参考 AudioBook 示例 AVSessionController）：
// 创建/复用媒体会话，上报元数据与播放态，接管播控中心、锁屏的
// 播放/暂停/上一章/下一章命令；点击媒体卡片拉起应用。
export class TtsAvSession {
  private static session: avSession.AVSession | undefined = undefined;
  private static cmds: TtsSessionCommands | undefined = undefined;
  private static settingUp: boolean = false;

  // 创建（或复用）会话并刷新元数据与命令回调；并发调用时以后到的元数据为准
  static async setup(context: common.UIAbilityContext, meta: TtsSessionMeta,
    commands: TtsSessionCommands): Promise<void> {
    TtsAvSession.cmds = commands;
    if (TtsAvSession.settingUp) {
      return;
    }
    TtsAvSession.settingUp = true;
    try {
      if (TtsAvSession.session === undefined) {
        const s: avSession.AVSession = await avSession.createAVSession(context, 'novel_tts', 'audio');
        TtsAvSession.session = s;
        await s.activate().catch((e: BusinessError): void => {
          hilog.warn(DOMAIN, TAG, 'activate failed: %{public}s', e.message);
        });
        TtsAvSession.setLaunchAbility(context);
        s.on('play', (): void => {
          const c = TtsAvSession.cmds;
          if (c !== undefined) {
            c.onPlay();
          }
        });
        s.on('pause', (): void => {
          const c = TtsAvSession.cmds;
          if (c !== undefined) {
            c.onPause();
          }
        });
        s.on('playNext', (): void => {
          const c = TtsAvSession.cmds;
          if (c !== undefined) {
            c.onNext();
          }
        });
        s.on('playPrevious', (): void => {
          const c = TtsAvSession.cmds;
          if (c !== undefined) {
            c.onPrev();
          }
        });
      }
      await TtsAvSession.applyMeta(TtsAvSession.session, meta);
    } catch (e) {
      // 会话创建失败不阻断听书（仅失去播控中心控制）
      hilog.warn(DOMAIN, TAG, 'setup failed: %{public}s', `${e}`);
      TtsAvSession.session = undefined;
    } finally {
      TtsAvSession.settingUp = false;
    }
  }

  // 上报播放态（播放/暂停）
  static setPlaying(playing: boolean): void {
    const s = TtsAvSession.session;
    if (s === undefined) {
      return;
    }
    s.setAVPlaybackState({
      state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE
    }).catch((e: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'setPlaying failed: %{public}s', e.message);
    });
  }

  // 销毁会话（停止听书时调用）
  static async destroy(): Promise<void> {
    const s = TtsAvSession.session;
    TtsAvSession.session = undefined;
    TtsAvSession.cmds = undefined;
    if (s === undefined) {
      return;
    }
    try {
      s.off('play');
      s.off('pause');
      s.off('playNext');
      s.off('playPrevious');
      await s.destroy();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'destroy failed: %{public}s', `${e}`);
    }
  }

  // 刷新媒体卡片元数据（含本地封面 PixelMap）
  private static async applyMeta(s: avSession.AVSession, meta: TtsSessionMeta): Promise<void> {
    const md: avSession.AVMetadata = {
      assetId: meta.assetId,
      title: meta.title,
      artist: meta.artist,
      avQueueName: meta.queueName,
      avQueueId: meta.queueId
    };
    if (meta.coverUri !== '') {
      try {
        const source: image.ImageSource = image.createImageSource(meta.coverUri);
        const pm: image.PixelMap = await source.createPixelMap();
        md.mediaImage = pm;
      } catch (e) {
        // 封面加载失败不阻断元数据上报
      }
    }
    await s.setAVMetadata(md).catch((e: BusinessError): void => {
      hilog.warn(DOMAIN, TAG, 'setAVMetadata failed: %{public}s', e.message);
    });
  }

  // 点击媒体卡片拉起应用
  private static setLaunchAbility(context: common.UIAbilityContext): void {
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }
      ],
      operationType: wantAgent.OperationType.START_ABILITIES,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    wantAgent.getWantAgent(info).then((agent: WantAgent) => {
      const s = TtsAvSession.session;
      if (s !== undefined) {
        s.setLaunchAbility(agent).catch((e: BusinessError): void => {
          hilog.warn(DOMAIN, TAG, 'setLaunchAbility failed: %{public}s', e.message);
        });
      }
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'getWantAgent failed: %{public}s', e.message);
    });
  }
}
