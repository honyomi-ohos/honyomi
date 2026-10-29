// 笔记富文本 markdown 子集（与 Mihon compose-richeditor 的序列化格式互通）：
// **粗体** / *斜体* / <u>下划线</u> / ~~删除线~~ / "- " 无序列表 / "N. " 有序列表 / 空段落 <br>。
// parse：markdown → 带样式标志的纯文本片段（NoteSegment），供 RichEditor 装载与 Text+Span 渲染；
// serialize：编辑器片段 → 同格式 markdown，保证与 Mihon 数据互读、往返稳定。

// 无序列表展示前缀：编辑器内以字面文本存在，序列化时还原为 "- "
const UL_DISPLAY: string = '• ';

// 富文本片段：文本 + 四个可叠加的样式标志
export class NoteSegment {
  text: string;
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strike: boolean;

  constructor(text: string, bold: boolean, italic: boolean, underline: boolean, strike: boolean) {
    this.text = text;
    this.bold = bold;
    this.italic = italic;
    this.underline = underline;
    this.strike = strike;
  }

  // 四个样式标志是否完全一致（用于相邻片段合并）
  sameStyle(other: NoteSegment): boolean {
    return this.bold === other.bold && this.italic === other.italic
      && this.underline === other.underline && this.strike === other.strike;
  }
}

// 行内标记匹配结果（区间为左闭右开）
interface InlineMatch {
  start: number;
  innerStart: number;
  innerEnd: number;
  end: number;
  bold: boolean;
  italic: boolean;
  strike: boolean;
  underline: boolean;
}

export class NotesMarkdown {
  // markdown → 展示片段（换行以 '\n' 并入文本；无序列表 "- "/"* " 转 "• "；有序列表原样保留）
  static parse(md: string): NoteSegment[] {
    const out: NoteSegment[] = [];
    if (md === '') {
      return out;
    }
    const lines: string[] = md.split('\n');
    for (let i = 0; i < lines.length; i++) {
      let line: string = lines[i];
      // Mihon 空段落序列化为 <br>
      if (line.trim() === '<br>') {
        line = '';
      }
      const ul: RegExpMatchArray | null = line.match(/^([ \t]*)[-*] /);
      if (ul !== null) {
        line = `${ul[1]}${UL_DISPLAY}${line.substring(ul[0].length)}`;
      }
      if (i > 0) {
        out.push(new NoteSegment('\n', false, false, false, false));
      }
      NotesMarkdown.parseInline(line, false, false, false, false, out);
    }
    return NotesMarkdown.merge(out);
  }

  // 展示片段 → markdown（与 Mihon richeditor 序列化格式一致：
  // 打开顺序 ** * ~~ <u>，关闭顺序 </u> ~~ * **；无序列表还原为 "- "）
  static serialize(segments: NoteSegment[]): string {
    const lines: NoteSegment[][] = NotesMarkdown.splitLines(segments);
    const mdLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      mdLines.push(NotesMarkdown.serializeLine(lines[i]));
    }
    return mdLines.join('\n');
  }

  // 合并相邻同样式片段（空文本片段丢弃）
  static merge(segments: NoteSegment[]): NoteSegment[] {
    const out: NoteSegment[] = [];
    for (let i = 0; i < segments.length; i++) {
      const seg: NoteSegment = segments[i];
      if (seg.text === '') {
        continue;
      }
      const last: NoteSegment | undefined = out.length > 0 ? out[out.length - 1] : undefined;
      if (last !== undefined && last.sameStyle(seg)) {
        last.text += seg.text;
      } else {
        out.push(new NoteSegment(seg.text, seg.bold, seg.italic, seg.underline, seg.strike));
      }
    }
    return out;
  }

  // 片段纯文本拼接
  static plain(segments: NoteSegment[]): string {
    let s: string = '';
    for (let i = 0; i < segments.length; i++) {
      s += segments[i].text;
    }
    return s;
  }

  // 行内解析：按最早出现的标记递归拆分（***粗斜体*** → **粗** → *斜* → ~~删除线~~ → <u>下划线</u>）
  private static parseInline(text: string, bold: boolean, italic: boolean,
    underline: boolean, strike: boolean, out: NoteSegment[]): void {
    if (text === '') {
      return;
    }
    const m: InlineMatch | undefined = NotesMarkdown.firstMatch(text);
    if (m === undefined) {
      out.push(new NoteSegment(text, bold, italic, underline, strike));
      return;
    }
    if (m.start > 0) {
      out.push(new NoteSegment(text.substring(0, m.start), bold, italic, underline, strike));
    }
    NotesMarkdown.parseInline(text.substring(m.innerStart, m.innerEnd),
      bold || m.bold, italic || m.italic, underline || m.underline, strike || m.strike, out);
    NotesMarkdown.parseInline(text.substring(m.end), bold, italic, underline, strike, out);
  }

  // 在五种标记中选起点最早（同起点取最长）的匹配；无匹配返回 undefined
  private static firstMatch(text: string): InlineMatch | undefined {
    const candidates: InlineMatch[] = [];
    const bi: [number, number, number, number] | undefined = NotesMarkdown.findEnclosed(text, '***', '***');
    if (bi !== undefined) {
      candidates.push({
        start: bi[0], innerStart: bi[1], innerEnd: bi[2], end: bi[3],
        bold: true, italic: true, strike: false, underline: false
      });
    }
    const b: [number, number, number, number] | undefined = NotesMarkdown.findEnclosed(text, '**', '**');
    if (b !== undefined) {
      candidates.push({
        start: b[0], innerStart: b[1], innerEnd: b[2], end: b[3],
        bold: true, italic: false, strike: false, underline: false
      });
    }
    const it: [number, number, number, number] | undefined = NotesMarkdown.findEnclosed(text, '*', '*');
    if (it !== undefined) {
      candidates.push({
        start: it[0], innerStart: it[1], innerEnd: it[2], end: it[3],
        bold: false, italic: true, strike: false, underline: false
      });
    }
    const st: [number, number, number, number] | undefined = NotesMarkdown.findEnclosed(text, '~~', '~~');
    if (st !== undefined) {
      candidates.push({
        start: st[0], innerStart: st[1], innerEnd: st[2], end: st[3],
        bold: false, italic: false, strike: true, underline: false
      });
    }
    const un: [number, number, number, number] | undefined = NotesMarkdown.findEnclosed(text, '<u>', '</u>');
    if (un !== undefined) {
      candidates.push({
        start: un[0], innerStart: un[1], innerEnd: un[2], end: un[3],
        bold: false, italic: false, strike: false, underline: true
      });
    }
    let best: InlineMatch | undefined = undefined;
    for (let i = 0; i < candidates.length; i++) {
      const c: InlineMatch = candidates[i];
      if (best === undefined || c.start < best.start || (c.start === best.start && c.end > best.end)) {
        best = c;
      }
    }
    return best;
  }

  // 查找 open…close 包裹的最早闭合区间，返回 [start, innerStart, innerEnd, end]
  private static findEnclosed(text: string, open: string, close: string): [number, number, number, number] | undefined {
    const start: number = text.indexOf(open);
    if (start < 0) {
      return undefined;
    }
    const innerStart: number = start + open.length;
    const innerEnd: number = text.indexOf(close, innerStart);
    if (innerEnd < 0 || innerEnd <= innerStart) {
      return undefined;
    }
    return [start, innerStart, innerEnd, innerEnd + close.length];
  }

  // 按 '\n' 把片段序列拆成行（换行符本身不保留，行边界由数组表达）
  private static splitLines(segments: NoteSegment[]): NoteSegment[][] {
    const lines: NoteSegment[][] = [[]];
    for (let i = 0; i < segments.length; i++) {
      const seg: NoteSegment = segments[i];
      if (!seg.text.includes('\n')) {
        lines[lines.length - 1].push(seg);
        continue;
      }
      const parts: string[] = seg.text.split('\n');
      for (let j = 0; j < parts.length; j++) {
        if (j > 0) {
          lines.push([]);
        }
        if (parts[j] !== '') {
          lines[lines.length - 1].push(new NoteSegment(parts[j], seg.bold, seg.italic, seg.underline, seg.strike));
        }
      }
    }
    return lines;
  }

  // 单行序列化：剥离列表展示前缀 → 前缀转 markdown → 剩余片段按样式加标记
  private static serializeLine(line: NoteSegment[]): string {
    const merged: NoteSegment[] = NotesMarkdown.merge(line);
    if (merged.length === 0) {
      return '';
    }
    let full: string = '';
    for (let i = 0; i < merged.length; i++) {
      full += merged[i].text;
    }
    let prefix: string = '';
    let bodyOffset: number = 0;
    const ul: RegExpMatchArray | null = full.match(/^([ \t]*)• /);
    if (ul !== null) {
      prefix = `${ul[1]}- `;
      bodyOffset = ul[0].length;
    } else {
      const ol: RegExpMatchArray | null = full.match(/^[ \t]*\d+\. /);
      if (ol !== null) {
        prefix = ol[0];
        bodyOffset = ol[0].length;
      }
    }
    let out: string = prefix;
    let pos: number = 0;
    for (let i = 0; i < merged.length; i++) {
      const seg: NoteSegment = merged[i];
      const segStart: number = pos;
      const segEnd: number = pos + seg.text.length;
      pos = segEnd;
      if (segEnd <= bodyOffset) {
        continue;
      }
      const from: number = Math.max(segStart, bodyOffset);
      const piece: string = seg.text.substring(from - segStart, segEnd - segStart);
      if (piece === '') {
        continue;
      }
      const open: string = `${seg.bold ? '**' : ''}${seg.italic ? '*' : ''}${seg.strike ? '~~' : ''}${seg.underline ? '<u>' : ''}`;
      const close: string = `${seg.underline ? '</u>' : ''}${seg.strike ? '~~' : ''}${seg.italic ? '*' : ''}${seg.bold ? '**' : ''}`;
      out += open + piece + close;
    }
    return out;
  }
}
