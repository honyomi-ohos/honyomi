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
  // 单页文本可用宽高（vp）
  pageW: number = 0;
  pageH: number = 0;
  // 段间距（与渲染端 Column({space}) 一致）
  paraSpacing: number = 0;
  // 行高（切点收敛估算用）
  lineHeight: number = 32;
  // 段落 → 翻页页码映射（buildPages 填充，听书跟随翻页用）
  paraPage: number[] = [];
  private readonly measure: NovelMeasureFn;

  constructor(measure: NovelMeasureFn) {
    this.measure = measure;
  }

  // 按块贪心装页：一次性跑完增量游标（等价旧行为，供小章节/非渐进路径使用）
  buildPages(blocks: NovelBlock[]): NovelPage[] {
    const cursor = new PaginateCursor(this, blocks);
    cursor.step(0);
    this.paraPage = cursor.paraPage;
    return cursor.pages;
  }

  // 供 PaginateCursor 步进使用：测量文本块高度
  measureBlock(text: string, widthVp: number): number {
    return this.measure(text, widthVp);
  }

  // 在超长段落中找切点：capHint 为上一页的字符容量先验（0=未知）。
  // 先用实测行数按比例收敛切点，页面基本排满（剩余不足 0.08 行）即接受，
  // 省去精确二分的十余次测量；未收敛时才在剩余区间精确二分兜底，结果与全量二分一致
  // （供 PaginateCursor 切分步进复用）
  fitPrefix(text: string, width: number, maxH: number, capHint: number): number {
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

// 增量分页游标：把一次完整分页拆成可暂停的最小单元（一个块装页 / 超长段一次切分），
// 按时间预算步进，供阅读器把大章节分页切片到多帧执行（首批同步出页，后续异步补齐）。
// 每个单元至少执行一次再查预算，保证有进度；步进结果与一次性分页完全一致
export class PaginateCursor {
  // 已产出的页面（内部累加，step 返回其中新增部分）
  readonly pages: NovelPage[] = [];
  // 段落 → 页码映射（随分页增长，听书跟随翻页用）
  readonly paraPage: number[] = [];
  // 全部块处理完毕（含末页收尾）
  done: boolean = false;
  private readonly paginator: NovelPaginator;
  private readonly blocks: NovelBlock[];
  // 当前装页状态：未满页的段集合 / 已用高度
  private current: string[] = [];
  private used: number = 0;
  // 下一个待处理块
  private idx: number = 0;
  // 超长段切分状态：rest 非空表示正在切同一段；cap 为上一页字符容量先验
  private rest: string = '';
  private cap: number = 0;

  constructor(paginator: NovelPaginator, blocks: NovelBlock[]) {
    this.paginator = paginator;
    this.blocks = blocks;
  }

  // 推进分页直到预算耗尽或全部完成；budgetMs <= 0 表示不限时一次跑完。
  // 返回本次新产出的页面（与 pages 数组共享页对象引用）
  step(budgetMs: number): NovelPage[] {
    const start = this.pages.length;
    if (this.done) {
      return this.pages.slice(start);
    }
    const deadline = budgetMs > 0 ? Date.now() + budgetMs : -1;
    while (!this.done) {
      if (this.rest !== '') {
        this.splitStep();
      } else if (this.idx < this.blocks.length) {
        this.blockStep();
      } else {
        // 收尾：未满一页的 current 落页
        this.done = true;
        if (this.current.length > 0) {
          this.pages.push({ texts: this.current, imageUrl: '' });
          this.current = [];
        }
        break;
      }
      if (deadline > 0 && !this.done && Date.now() >= deadline) {
        break;
      }
    }
    return this.pages.slice(start);
  }

  // 处理一个块：插图独占一页；整段装得下走贪心装页；超长段进入切分状态
  private blockStep(): void {
    const p = this.paginator;
    const maxH = p.pageH;
    const width = p.pageW;
    const gap = p.paraSpacing;
    const block = this.blocks[this.idx];
    this.idx += 1;
    if (block.isImage) {
      // 插图：收尾当前文本页，插图独占新页
      if (this.current.length > 0) {
        this.pages.push({ texts: this.current, imageUrl: '' });
        this.current = [];
        this.used = 0;
      }
      this.pages.push({ texts: [], imageUrl: block.text });
      return;
    }
    let para = block.text;
    if (para === '') {
      para = ' ';
    }
    const h = p.measureBlock(para, width);
    if (h <= maxH) {
      const extra = this.current.length > 0 ? gap : 0;
      if (this.used + extra + h <= maxH) {
        this.paraPage[block.ttsIdx] = this.pages.length;
        this.current.push(para);
        this.used += extra + h;
        return;
      }
      // 当前页放不下：整段放入新页
      if (this.current.length > 0) {
        this.pages.push({ texts: this.current, imageUrl: '' });
      }
      this.paraPage[block.ttsIdx] = this.pages.length;
      this.current = [para];
      this.used = h;
      return;
    }
    // 整段超过一页：进入切分状态（当前页已收尾）
    if (this.current.length > 0) {
      this.pages.push({ texts: this.current, imageUrl: '' });
      this.current = [];
      this.used = 0;
    }
    this.paraPage[block.ttsIdx] = this.pages.length;
    this.rest = para;
    this.cap = 0;
  }

  // 超长段切分一步：产出一页或把剩余部分并入当前页
  private splitStep(): void {
    const p = this.paginator;
    const maxH = p.pageH;
    const width = p.pageW;
    const rest = this.rest;
    // 剩余不超过一页容量（先验）时才整段测量判断能否收尾，避免反复测量大段文本
    if (rest.length <= this.cap) {
      const hRest = p.measureBlock(rest, width);
      if (hRest <= maxH) {
        this.current.push(rest);
        this.used = hRest;
        this.rest = '';
        return;
      }
    }
    const fit = p.fitPrefix(rest, width, maxH, this.cap);
    if (fit <= 0) {
      // 页高不足一行：整段放入避免死循环
      this.current.push(rest);
      this.used = maxH;
      this.rest = '';
      return;
    }
    if (fit >= rest.length) {
      // 整个剩余部分一页内放得下：并入当前页，继续贪心装后续段落
      this.current.push(rest);
      this.used = p.measureBlock(rest, width);
      this.rest = '';
      return;
    }
    this.pages.push({ texts: [rest.substring(0, fit)], imageUrl: '' });
    this.rest = rest.substring(fit);
    this.cap = fit;
  }
}

// 一次完整分页的结果（页面与段落映射共享引用，缓存复用零拷贝）
export class PaginatedResult {
  readonly pages: NovelPage[];
  readonly paraPage: number[];

  constructor(pages: NovelPage[], paraPage: number[]) {
    this.pages = pages;
    this.paraPage = paraPage;
  }
}

// 整章分页结果 LRU 缓存：命中免重分页（切回上一章、改回设置等场景）。
// 页对象为共享引用，内存开销低；容量按章节计，超出淘汰最久未用条目
export class PaginateCache {
  private readonly capacity: number;
  private readonly keys: string[] = [];
  private readonly entries: PaginatedResult[] = [];

  constructor(capacity: number) {
    this.capacity = Math.max(1, capacity);
  }

  get(key: string): PaginatedResult | undefined {
    for (let i = 0; i < this.keys.length; i++) {
      if (this.keys[i] === key) {
        // 命中：移到末尾（最近使用）
        const k = this.keys.splice(i, 1)[0];
        this.keys.push(k);
        const e = this.entries.splice(i, 1)[0];
        this.entries.push(e);
        return e;
      }
    }
    return undefined;
  }

  put(key: string, result: PaginatedResult): void {
    for (let i = 0; i < this.keys.length; i++) {
      if (this.keys[i] === key) {
        this.entries[i] = result;
        return;
      }
    }
    this.keys.push(key);
    this.entries.push(result);
    if (this.keys.length > this.capacity) {
      this.keys.shift();
      this.entries.shift();
    }
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

  // 合并连续空行：两个及以上换行（含其间仅空格/制表/全角空格/NBSP 的行）
  // 折叠为单个换行；阅读器正文与听书段落共用，保证段落下标一致
  static mergeBlankLines(body: string): string {
    return body.replace(/(\r?\n[ \t\u00A0\u3000]*){2,}/g, '\n');
  }

  // 段落首行缩进：为无缩进的段落行前置 chars 个全角空格；
  // 空行与已带空白缩进（空格/制表/全角空格/NBSP）的行保持原样，避免二次缩进。
  // 缩进写入文本本身而非渲染属性：分页器与渲染用同一字符串测量，断行才一致
  static indentLine(line: string, chars: number): string {
    if (chars <= 0 || line === '') {
      return line;
    }
    const first = line.charAt(0);
    if (first === ' ' || first === '\t' || first === '\u3000' || first === '\u00A0') {
      return line;
    }
    let pad = '';
    for (let i = 0; i < chars; i++) {
      pad += '\u3000';
    }
    return pad + line;
  }

  // 多行正文整体加段落缩进（按 \n 拆分逐行处理）
  static indentLines(body: string, chars: number): string {
    if (chars <= 0 || body === '') {
      return body;
    }
    const lines = body.split('\n');
    for (let i = 0; i < lines.length; i++) {
      lines[i] = NovelChapterText.indentLine(lines[i], chars);
    }
    return lines.join('\n');
  }

  // 把 <img> 之间的 html 片段剥成纯文本段落，追加为文本块（跳过空段）；

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
}
