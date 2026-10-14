import { insightIntent, InsightIntentExecutor } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppKeys } from '../common/AppKeys';

const DOMAIN = 0x0001;

// 意图执行器（功能一步达）：小艺等系统入口通过 JumpFunctionPage 意图
// 拉起应用内功能页（书库/更新/历史/下载/搜索/统计等，见 insight_intent.json）。
// 复用 cardAction 导航通道（AppStorage），由 Index 页统一消费：
// - 应用已存活：@StorageLink @Watch 直接触发导航
// - 冷启动：onWindowStageCreate 先加载 Index，aboutToAppear 再消费暂存指令
export default class InsightIntentExecutorImpl extends InsightIntentExecutor {
  private static readonly JUMP_FUNCTION_PAGE: string = 'JumpFunctionPage';

  // 前台 UIAbility 意图执行：透传 pageId 至 cardAction 通道，Index 端统一路由
  onExecuteInUIAbilityForegroundMode(name: string, param: Record<string, Object>,
    pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
    if (name !== InsightIntentExecutorImpl.JUMP_FUNCTION_PAGE) {
      const unknown: insightIntent.ExecuteResult = {
        code: -1,
        result: { 'message': 'unknown intent' }
      };
      return Promise.resolve(unknown);
    }
    const pageIdVal = param['pageId'];
    if (typeof pageIdVal !== 'string' || pageIdVal === '') {
      const badParam: insightIntent.ExecuteResult = {
        code: -1,
        result: { 'message': 'pageId type error' }
      };
      return Promise.resolve(badParam);
    }
    const payload: Record<string, string | number> = {
      'target': pageIdVal,
      'mangaId': 0,
      'chapterId': 0,
      'contentType': ''
    };
    AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
    hilog.info(DOMAIN, 'Mihon', 'insight intent jump to %{public}s', pageIdVal);
    const ok: insightIntent.ExecuteResult = {
      code: 0,
      result: { 'message': 'Intent execute success' }
    };
    return Promise.resolve(ok);
  }
}
