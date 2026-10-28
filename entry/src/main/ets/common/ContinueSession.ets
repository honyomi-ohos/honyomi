import { url } from '@kit.ArkTS';
import { ChapterRecord, MangaRecord } from '../model/Models';

// 跨端内容会话（进程内存快照）：应用接续（onContinue 源端）与碰一碰
// （knockShare 分享、serviceInteraction 应用间推送）同步读取的"当前内容"。
// 阅读器 / 播放器 / 听书服务随章节加载与进度变化刷新本会话。
export class ContinueSession {
  // App Linking 域名：module.json5 的 skills 配置、服务器 /.well-known 校验文件须与此一致
  static readonly APP_LINK_HOST: string = 'api.honyomi.shuey.fun';
  private static readonly APP_LINK_PATH: string = 'https://api.honyomi.shuey.fun/read';

  private static active: boolean = false;
  private static contentType: string = '';
  private static sourceKey: string = '';
  private static mangaUrl: string = '';
  private static chapterUrl: string = '';
  private static title: string = '';
  private static chapterName: string = '';
  // 进度语义随内容类型：漫画=页码，小说=千分比(0-1000)，视频=播放位置毫秒
  private static progress: number = 0;

  static isActive(): boolean {
    return ContinueSession.active;
  }

  static titleText(): string {
    return ContinueSession.title;
  }

  static chapterNameText(): string {
    return ContinueSession.chapterName;
  }

  // 章节加载/切换时刷新完整会话
  static update(contentType: string, manga: MangaRecord | undefined, chapter: ChapterRecord,
    progress: number): void {
    ContinueSession.active = true;
    ContinueSession.contentType = contentType;
    ContinueSession.chapterUrl = chapter.url;
    ContinueSession.chapterName = chapter.name;
    ContinueSession.progress = Math.floor(progress);
    if (manga !== undefined) {
      ContinueSession.sourceKey = manga.sourceKey;
      ContinueSession.mangaUrl = manga.url;
      ContinueSession.title = manga.title;
    }
  }

  // 翻页/播放进度变化时的轻量刷新
  static updateProgress(progress: number): void {
    if (!ContinueSession.active) {
      return;
    }
    ContinueSession.progress = Math.floor(progress);
  }

  // 会话 JSON：应用接续 wantParam 与 serviceInteraction 消息体共用；无活动会话返回空串
  static toJson(): string {
    if (!ContinueSession.active) {
      return '';
    }
    const payload: Record<string, string | number> = {
      'target': 'continue',
      'contentType': ContinueSession.contentType,
      'sourceKey': ContinueSession.sourceKey,
      'mangaUrl': ContinueSession.mangaUrl,
      'chapterUrl': ContinueSession.chapterUrl,
      'page': ContinueSession.progress,
      'title': ContinueSession.title,
      'chapterName': ContinueSession.chapterName
    };
    return JSON.stringify(payload);
  }

  // App Linking 链接（碰一碰分享内容）；无活动会话时回退应用主页链接
  static toAppLink(): string {
    if (!ContinueSession.active) {
      return `https://${ContinueSession.APP_LINK_HOST}/`;
    }
    const link: string = ContinueSession.APP_LINK_PATH +
      `?src=${encodeURIComponent(ContinueSession.sourceKey)}` +
      `&m=${encodeURIComponent(ContinueSession.mangaUrl)}` +
      `&c=${encodeURIComponent(ContinueSession.chapterUrl)}` +
      `&p=${ContinueSession.progress}` +
      `&ct=${encodeURIComponent(ContinueSession.contentType)}` +
      `&t=${encodeURIComponent(ContinueSession.title)}`;
    return link;
  }

  // 解析 App Linking（对端经分享拉起时的 want.uri）为 cardAction 载荷；
  // 非本应用链接或参数不全返回 undefined
  static parseAppLink(uri: string): Record<string, string | number> | undefined {
    if (uri.indexOf(ContinueSession.APP_LINK_PATH) !== 0) {
      return undefined;
    }
    try {
      const parsed = url.URL.parseURL(uri);
      const src = parsed.params.get('src') ?? '';
      const mangaUrl = parsed.params.get('m') ?? '';
      if (src === '' || mangaUrl === '') {
        return undefined;
      }
      const pageRaw = Number(parsed.params.get('p') ?? '0');
      const payload: Record<string, string | number> = {
        'target': 'continue',
        'contentType': parsed.params.get('ct') ?? '',
        'sourceKey': src,
        'mangaUrl': mangaUrl,
        'chapterUrl': parsed.params.get('c') ?? '',
        'page': Number.isFinite(pageRaw) ? Math.floor(pageRaw) : 0,
        'title': parsed.params.get('t') ?? '',
        'chapterName': ''
      };
      return payload;
    } catch (e) {
      return undefined;
    }
  }
}
