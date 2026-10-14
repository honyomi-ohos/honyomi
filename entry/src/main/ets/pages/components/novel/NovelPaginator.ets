// 小说分页引擎（纯逻辑）：文本测量分页、超长段落二分切分、html 正文块解析。
// 从 NovelReaderPage 抽出（Wave 3I）；文本测量依赖 UIContext 的 measureTextSize，
// 由页面注入测量函数，本类不持有任何 UI 依赖。

// 章节正文块：文本段或插图（插件正文里的 <img> 解析而来）
export interface NovelBlock {
  isImage: boolean;
  // 文本段内容；图片块的图片 URL
  text: string;
  // 文本段在听书段落序列中的序号（图片块为 -1）
  ttsIdx: number;
}

// 翻页模式的单页：普通页为段落集合，插图页 imageUrl 非空、独占整页
export interface NovelPage {
  texts: string[];
  imageUrl: string;
}

// 双页中缝宽度（Divider 两侧 margin 12 + 1 线宽）
export const SPINE_W: number = 25;
// pageAt 越界时共享的空页对象（避免每次调用新建对象字面量）
export const EMPTY_NOVEL_PAGE: NovelPage = { texts: [], imageUrl: '' };

// 文本测量函数：返回文本在指定宽度下的渲染高度（vp），与渲染端 fontSize/lineHeight 一致
export type NovelMeasureFn = (text: string, widthVp: number) => number;

// 分页引擎：页面尺寸/间距配置由页面在每次分页前同步进来
export class NovelPaginator {
  private readonly measure: NovelMeasureFn;
  // 单页文本可用宽高（vp）
  pageW: number = 0;
  pageH: number = 0;
  // 段间距（与渲染端 Column({space}) 一致）
  paraSpacing: number = 0;
  // 行高（切点收敛估算用）
  lineHeight: number = 32;
  // 段落 → 翻页页码映射（buildPages 填充，听书跟随翻页用）
  paraPage: number[] = [];

  constructor(measure: NovelMeasureFn) {
    this.measure = measure;
  }

  // 按块贪心装页（段间计入 paraSpacing，与渲染端 Column({space}) 一致）；超长段落按测量二分切分；
  // 插图块独占一页（imageUrl 非空）。同时记录 paraPage[i]：第 i 个文本段所在的页码（听书跟随翻页用）
  buildPages(blocks: NovelBlock[]): NovelPage[] {
    const pages: NovelPage[] = [];
    const paraPage: number[] = [];
    const maxH = this.pageH;
    const width = this.pageW;
    const gap = this.paraSpacing;
    let current: string[] = [];
    let used = 0;
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      if (block.isImage) {
        // 插图：收尾当前文本页，插图独占新页
        if (current.length > 0) {
          pages.push({ texts: current, imageUrl: '' });
          current = [];
          used = 0;
        }
        pages.push({ texts: [], imageUrl: block.text });
        continue;
      }
      let para = block.text;
      if (para === '') {
        para = ' ';
      }
      const h = this.measure(para, width);
      if (h <= maxH) {
        const extra = current.length > 0 ? gap : 0;
        if (used + extra + h <= maxH) {
          paraPage[block.ttsIdx] = pages.length;
          current.push(para);
          used += extra + h;
          continue;
        }
        // 当前页放不下：整段放入新页
        if (current.length > 0) {
          pages.push({ texts: current, imageUrl: '' });
        }
        paraPage[block.ttsIdx] = pages.length;
        current = [para];
        used = h;
        continue;
      }
      // 整段超过一页：按字符切分
      if (current.length > 0) {
        pages.push({ texts: current, imageUrl: '' });
        current = [];
        used = 0;
      }
      paraPage[block.ttsIdx] = pages.length;
      let rest = para;
      // 每页可容纳字符数的先验（0=未知）：由上一次切点更新；
      // 剩余不超过一页容量时才整段测量判断能否收尾，避免反复测量大段文本
      let cap = 0;
      while (rest.length > 0) {
        if (rest.length <= cap) {
          const hRest = this.measure(rest, width);
          if (hRest <= maxH) {
            current.push(rest);
            used = hRest;
            break;
          }
        }
        const fit = this.fitPrefix(rest, width, maxH, cap);
        if (fit <= 0) {
          // 页高不足一行：整段放入避免死循环
          current.push(rest);
          used = maxH;
          break;
        }
        if (fit >= rest.length) {
          // 整个剩余部分一页内放得下：并入当前页，继续贪心装后续段落
          current.push(rest);
          used = this.measure(rest, width);
          break;
        }
        pages.push({ texts: [rest.substring(0, fit)], imageUrl: '' });
        rest = rest.substring(fit);
        cap = fit;
      }
    }
    if (current.length > 0) {
      pages.push({ texts: current, imageUrl: '' });
    }
    this.paraPage = paraPage;
    return pages;
  }

  // 在超长段落中找切点：capHint 为上一页的字符容量先验（0=未知）。
  // 先用实测行数按比例收敛切点，页面基本排满（剩余不足 0.08 行）即接受，
  // 省去精确二分的十余次测量；未收敛时才在剩余区间精确二分兜底，结果与全量二分一致
  private fitPrefix(text: string, width: number, maxH: number, capHint: number): number {
    const len = text.length;
    if (len <= 0) {
      return 0;
    }
    const linesPerPage = maxH / this.lineHeight;
    let best = 0;
    let hiFail = len + 1;
    let k = capHint > 0 ? Math.max(1, Math.min(len, Math.round(capHint))) : Math.ceil(len / 2);
    let accepted = false;
    for (let iter = 0; iter < 4 && !accepted && k > best && k < hiFail; iter++) {
      const h = this.measure(text.substring(0, k), width);
      if (h <= maxH) {
        best = k;
        if (k >= len) {
          break;
        }
        const linesUsed = Math.max(1, h / this.lineHeight);
        const linesLeft = linesPerPage - linesUsed;
        if (linesLeft < 0.08) {
          accepted = true;
          break;
        }
        // 按剩余行数与每行字符数估算可再容纳的字符量
        let nk = k + Math.max(1, Math.round(linesLeft * (k / linesUsed)));
        if (nk >= hiFail) {
          nk = hiFail - 1;
        }
        if (nk <= best) {
          break;
        }
        k = nk;
      } else {
        hiFail = k;
        const linesUsed = Math.max(1, h / this.lineHeight);
        const over = linesUsed - linesPerPage;
        const nk = k - Math.max(1, Math.round(over * (k / linesUsed)));
        if (nk <= best) {
          break;
        }
        k = nk;
      }
    }
    if (!accepted) {
      // 未整页收敛：剩余区间精确二分，保证与全量二分结果一致
      while (best + 1 < hiFail) {
        const mid = Math.floor((best + hiFail) / 2);
        if (this.measure(text.substring(0, mid), width) <= maxH) {
          best = mid;
        } else {
          hiFail = mid;
        }
      }
    }
    // 避免切开代理对（emoji 等）
    if (best > 0 && best < text.length) {
      const code = text.charCodeAt(best - 1);
      if (code >= 0xD800 && code <= 0xDBFF) {
        best -= 1;
      }
    }
    return best;
  }
}

// 章节正文解析（纯静态）：html 识别、「文本段 + 插图」块序列、纯文本块视图
export class NovelChapterText {
  // 按开头若干字符推断正文是否为 html
  static looksLikeHtml(text: string): boolean {
    const head = text.substring(0, 240).toLowerCase();
    return head.indexOf('<p') >= 0 || head.indexOf('<br') >= 0 || head.indexOf('<div') >= 0 ||
      head.indexOf('<html') >= 0;
  }

  // 解析 html 章节为「文本段 + 插图」块序列：正文以 <img> 标记插图，
  // 滚动模式内嵌渲染、翻页模式插图独占一页；非 html 返回空数组
  static parseBlocks(html: boolean, body: string): NovelBlock[] {
    const blocks: NovelBlock[] = [];
    if (!html) {
      return blocks;
    }
    let seq = 0;
    const imgRe = /<img\b[^>]*>/gi;
    let idx = 0;
    let match = imgRe.exec(body);
    while (match !== null) {
      seq = NovelChapterText.pushTextBlocks(body.substring(idx, match.index), blocks, seq);
      const src = NovelChapterText.imgSrcOf(match[0]);
      if (src !== '') {
        const image: NovelBlock = { isImage: true, text: src, ttsIdx: -1 };
        blocks.push(image);
      }
      idx = match.index + match[0].length;
      match = imgRe.exec(body);
    }
    NovelChapterText.pushTextBlocks(body.substring(idx), blocks, seq);
    return blocks;
  }

  // html 片段剥成纯文本：块级标签（br/p/div）转换行、去其余标签、还原常见实体；
  // 首尾空白一并去除。无插图 html 正文经此归一为纯文本，走统一的分页/渲染路径
  static htmlToPlain(segment: string): string {
    return segment
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<\/div>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&amp;/g, '&')
      .trim();
  }

  // 把 <img> 之间的 html 片段剥成纯文本段落，追加为文本块（跳过空段）；
  // 返回递增后的文本段序号
  private static pushTextBlocks(segment: string, blocks: NovelBlock[], ttsSeq: number): number {
    const lines = NovelChapterText.htmlToPlain(segment).split('\n');
    let seq = ttsSeq;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line === '') {
        continue;
      }
      const block: NovelBlock = { isImage: false, text: line, ttsIdx: seq };
      blocks.push(block);
      seq += 1;
    }
    return seq;
  }

  // 提取 <img> 标签的 src 属性
  private static imgSrcOf(tag: string): string {
    const match = /\ssrc\s*=\s*["']([^"']+)["']/i.exec(tag);
    if (match === null) {
      return '';
    }
    return match[1].trim();
  }

  // 纯文本章节的块视图：每行一个文本块（与 body.split('\n') 等价）
  static plainBlocks(body: string): NovelBlock[] {
    const paras = body.split('\n');
    const out: NovelBlock[] = [];
    for (let i = 0; i < paras.length; i++) {
      const block: NovelBlock = { isImage: false, text: paras[i], ttsIdx: i };
      out.push(block);
    }
    return out;
  }
}
