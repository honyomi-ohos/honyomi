import { insightIntent, InsightIntentEntry, InsightIntentEntryExecutor } from '@kit.AbilityKit';
import { AppKeys } from '../common/AppKeys';

// 快进指令载荷（AppStorage videoSeek 键，VideoPlayerPage 消费）
interface VideoSeekPayload {
  mode: string; // delta 相对位移 | absolute 绝对位置 | end 片尾
  ms: number;
  ts: number; // 时间戳：同一指令重复下发也保证被消费
}

// 自定义意图：视频快进/跳转时间（"用 Mihon 快进30秒"、"跳到第10分钟"）。
// 视频播放页在前台时由其监听 videoSeek 键执行 seek；无视频页打开时指令静默忽略。
@InsightIntentEntry({
  intentName: 'VideoSeek',
  domain: 'ReadingDomain',
  intentVersion: '1.0.1',
  displayName: '视频快进跳转',
  icon: $r('app.media.ic_forward_10'),
  llmDescription: '在视频播放中快进、后退或跳转到指定时间点。当用户正在用本应用看视频并说"快进30秒"、"后退1分钟"、"跳到第10分钟"、"回到开头"时使用。',
  keywords: ['快进', '后退', '跳转到时间'],
  abilityName: 'EntryAbility',
  executeMode: [insightIntent.ExecuteMode.UI_ABILITY_FOREGROUND],
  parameters: {
    'type': 'object',
    'description': '视频快进/跳转指令',
    'properties': {
      'seekQuery': {
        'type': 'string',
        'description': '快进/跳转描述，例如"快进30秒"、"后退1分钟"、"跳到第10分钟"、"回到开头"',
        'minLength': 1
      }
    },
    'required': ['seekQuery']
  }
})
export default class VideoSeekImpl extends InsightIntentEntryExecutor<string> {
  public seekQuery: string = '';

  // "跳到(第)X分钟(零Y秒)" → absolute；"回到开头/跳到结尾" → absolute 0 / end
  private static parseSeek(query: string): VideoSeekPayload | undefined {
    const s: string = query.replace(/\s+/g, '').toLowerCase();
    if (s === '') {
      return undefined;
    }
    if (s.indexOf('开头') >= 0 || s.indexOf('开始') >= 0) {
      return { mode: 'absolute', ms: 0, ts: 0 };
    }
    if (s.indexOf('结尾') >= 0 || s.indexOf('最后') >= 0) {
      return { mode: 'end', ms: 0, ts: 0 };
    }
    const backward: boolean = s.indexOf('后退') >= 0 || s.indexOf('快退') >= 0 ||
      s.indexOf('回退') >= 0 || s.indexOf('倒退') >= 0;
    const absolute: boolean = s.indexOf('跳') >= 0 || s.indexOf('移到') >= 0;
    let ms: number = 0;
    let matched: boolean = false;
    const minMatch: RegExpMatchArray | null = s.match(/(\d+)分/);
    if (minMatch !== null) {
      ms += parseInt(minMatch[1]) * 60000;
      matched = true;
    }
    const secMatch: RegExpMatchArray | null = s.match(/(\d+)秒/);
    if (secMatch !== null) {
      ms += parseInt(secMatch[1]) * 1000;
      matched = true;
    }
    if (!matched) {
      const bareMatch: RegExpMatchArray | null = s.match(/\d+/);
      if (bareMatch !== null) {
        ms = parseInt(bareMatch[0]) * 1000;
        matched = true;
      }
    }
    if (!matched) {
      return undefined;
    }
    if (backward) {
      return { mode: 'delta', ms: -ms, ts: 0 };
    }
    if (absolute) {
      return { mode: 'absolute', ms: ms, ts: 0 };
    }
    return { mode: 'delta', ms: ms, ts: 0 };
  }

  // 解析中文快进/跳转描述：
  // "快进/前进 X(秒|分钟)" → delta 正；"后退/快退 X" → delta 负；

  private static result(code: number, msg: string): insightIntent.IntentResult<string> {
    return { code: code, result: msg };
  }

  onExecute(): Promise<insightIntent.IntentResult<string>> {
    const query: string = this.seekQuery.trim();
    const cmd: VideoSeekPayload | undefined = VideoSeekImpl.parseSeek(query);
    if (cmd === undefined) {
      return Promise.resolve(VideoSeekImpl.result(-1, `无法理解快进指令："${query}"`));
    }
    cmd.ts = Date.now();
    AppStorage.setOrCreate(AppKeys.VIDEO_SEEK, JSON.stringify(cmd));
    return Promise.resolve(VideoSeekImpl.result(0, `已执行：${query}`));
  }
}
