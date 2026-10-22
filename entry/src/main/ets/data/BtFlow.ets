/*
 * BtFlow — BT 下载决策流（引擎选择 + 系统移交）。
 *
 * BT 插件（AnimeGarden / 蜜柑计划 / Nyaa.land 等）的章节是 magnet/.torrent
 * 直链，不支持在线流播：首次使用时询问用户下载方式——
 *   「下载内置引擎」→ 记住选择，走 torrent HSP（后续不再询问）
 *   「交给系统应用」→ 记住选择，magnet/.torrent 移交系统应用选择器（如迅雷）
 * 选择持久化于 Settings.btEngineChoice（'ask' 未决 / 'module' / 'system'），
 * 设置页「下载」分类下可随时更改。
 */
import { common, Want } from '@kit.AbilityKit';
import { ComponentContent, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { DownloadService } from './DownloadService';
import { BtModule } from './BtModule';
import { BtEngineChoiceBuilder, BtEngineChoiceParams } from '../pages/components/BtEngineChoiceDialog';

// acquireEngineChoice 进行中的 resolver（同一时刻至多一个选择弹窗）
let btChoiceResolve: ((choice: string) => void) | undefined = undefined;
// 选择弹窗实例（finishChoice 关闭/释放用）
let btChoiceUi: UIContext | undefined = undefined;
let btChoiceContent: ComponentContent<BtEngineChoiceParams> | undefined = undefined;

export class BtFlow {
  // 读取/询问 BT 引擎选择：已决（module/system）直接返回，未决弹窗询问。
  // 返回 'module' | 'system' | 'cancel'（取消不落库，下次继续询问）
  static async acquireEngineChoice(ui: UIContext): Promise<string> {
    const saved = Settings.getBtEngineChoice();
    if (saved === 'module' || saved === 'system') {
      return saved;
    }
    return new Promise<string>((resolve: (choice: string) => void) => {
      btChoiceResolve = resolve;
      const params = new BtEngineChoiceParams();
      params.onPick = (choice: string): void => {
        BtFlow.finishChoice(choice);
      };
      params.onCancel = (): void => {
        BtFlow.finishChoice('cancel');
      };
      const content = new ComponentContent<BtEngineChoiceParams>(ui, wrapBuilder(BtEngineChoiceBuilder), params);
      btChoiceUi = ui;
      btChoiceContent = content;
      ui.getPromptAction().openCustomDialog(content, {
        alignment: DialogAlignment.Center,
        autoCancel: true,
        onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
          dismissDialogAction.dismiss();
          BtFlow.finishChoice('cancel');
        }
      }).catch((e: BusinessError) => {
        hilog.warn(0x0001, 'BtFlow', 'open choice dialog failed: %{public}s', `${e}`);
        BtFlow.finishChoice('cancel');
      });
    });
  }

  private static finishChoice(choice: string): void {
    if (choice === 'module' || choice === 'system') {
      Settings.setBtEngineChoice(choice);
    }
    const ui = btChoiceUi;
    const content = btChoiceContent;
    const resolve = btChoiceResolve;
    btChoiceUi = undefined;
    btChoiceContent = undefined;
    btChoiceResolve = undefined;
    if (ui !== undefined && content !== undefined) {
      ui.getPromptAction().closeCustomDialog(content)
        .then((): void => {
          content.dispose();
        })
        .catch((): void => {
          content.dispose();
        });
    }
    if (resolve !== undefined) {
      resolve(choice);
    }
  }

  // magnet/.torrent 移交系统应用选择器（如迅雷）；无应用可处理时回退浏览器打开
  static async handOffToSystem(ui: UIContext, url: string): Promise<boolean> {
    const context: common.UIAbilityContext | undefined = Util.hostAbilityContext(ui);
    if (context === undefined) {
      return false;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url,
      type: url.startsWith('magnet:') ? 'application/x-bittorrent' : undefined
    };
    try {
      await context.startAbility(want);
      Util.toastRes(ui, $r('app.string.bt_handoff_started'));
      return true;
    } catch (e) {
      hilog.warn(0x0001, 'BtFlow', 'handoff startAbility failed: %{public}s', `${e}`);
      // 无应用注册该类型：回退浏览器打开（可触发系统下载）
      try {
        const fallback: Want = {
          action: 'ohos.want.action.viewData',
          uri: url,
          entities: ['entity.system.browsable']
        };
        await context.startAbility(fallback);
        return true;
      } catch (e2) {
        Util.toastRes(ui, $r('app.string.bt_handoff_failed'));
        return false;
      }
    }
  }

  // 设置页额外 tracker 多行文本 → URL 列表（去空行/首尾空白）
  static extraTrackerList(): string[] {
    const raw = Settings.getBtExtraTrackers();
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

  // 限速设置变更/网络环境切换时即时生效：计费网络（蜂窝）按设置压低上传。
  // 引擎未启动/组件缺失静默（启动时由 ensureStarted 读取）
  static applyLimitsLive(): void {
    BtModule.setLimits(Settings.getBtDownloadLimitKb() * 1024, BtModule.effectiveUploadLimitBytes())
      .catch((): void => {
      });
  }

  // 分享率限制变更即时生效（引擎未启动静默）
  static applyShareRatioLive(): void {
    BtModule.setShareRatioLimit(Settings.getBtShareRatioLimit())
      .catch((): void => {
      });
  }

  // Peer 过滤规则变更即时生效（引擎未启动静默）
  static applyPeerFilterLive(): void {
    BtModule.setIpFilter(BtModule.peerFilterRules())
      .catch((): void => {
      });
  }

  // 顺序下载开关按设置应用到活动 BT 任务（引擎未启动静默）
  static applySequentialToTask(chapterId: number): void {
    const key = DownloadService.btKeyOf(chapterId);
    if (key >= 0) {
      BtModule.setSequential(key, Settings.getBtProgressive()).catch((): void => {
      });
    }
  }

  // 轮询等待（播放器等待流用）
  static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
