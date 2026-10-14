import { NovelChapterText } from '../pages/components/novel/NovelPaginator';

// 小说听书文本工具：章节正文 → 朗读段落序列、语种推断。
// 阅读器与听书播放服务（TtsPlaybackService）共用同一算法，
// 保证两端段落下标一致（高亮跟随、起播段落、进度均以同一序列为基准）。
export class TtsText {
  // 章节正文 → 朗读段落数组：
  // - html 含插图：取「文本段 + 插图」块序列中的文本块（与阅读器渲染路径一致）
  // - html 纯文本：剥除标签后按行拆分（保留空行，下标与阅读器旧实现一致）
  // - 纯文本：按行拆分
  static chapterParas(text: string): string[] {
    if (text === '') {
      return [];
    }
    const html = NovelChapterText.looksLikeHtml(text);
    if (!html) {
      return text.split('\n');
    }
    const blocks = NovelChapterText.parseBlocks(true, text);
    let hasImages = false;
    for (let i = 0; i < blocks.length; i++) {
      if (blocks[i].isImage) {
        hasImages = true;
        break;
      }
    }
    if (hasImages) {
      const out: string[] = [];
      for (let i = 0; i < blocks.length; i++) {
        if (!blocks[i].isImage) {
          out.push(blocks[i].text);
        }
      }
      return out;
    }
    // html 纯文本：剥成纯文本按行拆分（与阅读器对无插图 html 的正文归一一致，
    // 保证听书段落下标与阅读器渲染段落对齐）
    return NovelChapterText.htmlToPlain(text).split('\n');
  }

  // 按开头若干段采样推断语种（ASCII 过半判英文）
  static detectLang(paras: string[]): string {
    let ascii = 0;
    let total = 0;
    const sampleCount = Math.min(paras.length, 40);
    for (let i = 0; i < sampleCount; i++) {
      const s = paras[i];
      for (let j = 0; j < s.length; j++) {
        const c = s.charCodeAt(j);
        if (c > 32) {
          total++;
          if (c < 128) {
            ascii++;
          }
        }
      }
    }
    if (total > 0 && ascii * 2 > total) {
      return 'en-US';
    }
    return 'zh-CN';
  }
}
