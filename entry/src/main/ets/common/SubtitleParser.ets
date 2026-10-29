// SRT 字幕解析：BOM/CRLF/多行文本/HTML 标签与常见实体容错，
// 输出 SubCue 列表（毫秒时间轴），供播放器按当前进度取当前行
export class SubCue {
  startMs: number = 0;
  endMs: number = 0;
  text: string = '';
}

export class SubtitleParser {
  // 解析 SRT 文本；无法解析返回空数组
  static parseSrt(content: string): SubCue[] {
    let text: string = content;
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
      text = text.substring(1);
    }
    text = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const blocks: string[] = text.split(/\n{2,}/);
    const cues: SubCue[] = [];
    for (let i = 0; i < blocks.length; i++) {
      const cue: SubCue | undefined = SubtitleParser.parseBlock(blocks[i]);
      if (cue !== undefined) {
        cues.push(cue);
      }
    }
    cues.sort((a: SubCue, b: SubCue): number => a.startMs - b.startMs);
    return cues;
  }

  // 当前时刻命中的字幕行（多条取首条）；无命中返回空串
  static activeText(cues: SubCue[], posMs: number): string {
    for (let i = 0; i < cues.length; i++) {
      const cue: SubCue = cues[i];
      if (posMs >= cue.startMs && posMs < cue.endMs) {
        return cue.text;
      }
      if (cue.startMs > posMs) {
        break;
      }
    }
    return '';
  }

  // ---- 内部实现 ----

  // 单个字幕块：可选序号行 + 时间行（00:00:01,000 --> 00:00:04,000）+ 文本行
  private static parseBlock(block: string): SubCue | undefined {
    const lines: string[] = block.split('\n');
    let idx: number = 0;
    // 跳过序号行：纯数字行
    while (idx < lines.length && lines[idx].trim() === '') {
      idx++;
    }
    if (idx < lines.length && /^\d+$/.test(lines[idx].trim())) {
      idx++;
    }
    let timeIdx: number = -1;
    for (let i = idx; i < lines.length; i++) {
      if (lines[i].indexOf('-->') >= 0) {
        timeIdx = i;
        break;
      }
    }
    if (timeIdx < 0) {
      return undefined;
    }
    const segs: string[] = lines[timeIdx].split('-->');
    if (segs.length < 2) {
      return undefined;
    }
    const startMs: number = SubtitleParser.parseTime(segs[0]);
    const endMs: number = SubtitleParser.parseTime(segs[1]);
    if (startMs < 0 || endMs < 0 || endMs <= startMs) {
      return undefined;
    }
    const textParts: string[] = [];
    for (let i = timeIdx + 1; i < lines.length; i++) {
      const line: string = SubtitleParser.cleanLine(lines[i]);
      if (line !== '') {
        textParts.push(line);
      }
    }
    if (textParts.length === 0) {
      return undefined;
    }
    const cue: SubCue = new SubCue();
    cue.startMs = startMs;
    cue.endMs = endMs;
    cue.text = textParts.join('\n');
    return cue;
  }

  // 时间戳解析："hh:mm:ss,mmm" / "hh:mm:ss.mmm" / "hh:mm:ss" / "mm:ss,mmm"，非法返回 -1
  private static parseTime(raw: string): number {
    const trimmed: string = raw.trim().split(' ')[0];
    let m: RegExpMatchArray | null = trimmed.match(/^(\d+):(\d{1,2}):(\d{1,2})[,.](\d{1,3})$/);
    if (m !== null && m.length === 5) {
      const h: number = parseInt(m[1] ?? '0', 10);
      const mi: number = parseInt(m[2] ?? '0', 10);
      const s: number = parseInt(m[3] ?? '0', 10);
      const ms: number = parseInt((m[4] ?? '0').padEnd(3, '0'), 10);
      return ((h * 60 + mi) * 60 + s) * 1000 + ms;
    }
    m = trimmed.match(/^(\d+):(\d{1,2}):(\d{1,2})$/);
    if (m !== null && m.length === 4) {
      const h: number = parseInt(m[1] ?? '0', 10);
      const mi: number = parseInt(m[2] ?? '0', 10);
      const s: number = parseInt(m[3] ?? '0', 10);
      return ((h * 60 + mi) * 60 + s) * 1000;
    }
    m = trimmed.match(/^(\d+):(\d{1,2})[,.](\d{1,3})$/);
    if (m !== null && m.length === 4) {
      const mi: number = parseInt(m[1] ?? '0', 10);
      const s: number = parseInt(m[2] ?? '0', 10);
      const ms: number = parseInt((m[3] ?? '0').padEnd(3, '0'), 10);
      return (mi * 60 + s) * 1000 + ms;
    }
    return -1;
  }

  // 文本行清洗：去 HTML 标签与常见实体
  private static cleanLine(line: string): string {
    let out: string = line.replace(/<[^>]*>/g, '');
    out = out.replace(/&nbsp;/g, ' ');
    out = out.replace(/&lt;/g, '<');
    out = out.replace(/&gt;/g, '>');
    out = out.replace(/&quot;/g, '"');
    out = out.replace(/&#39;/g, '\'');
    out = out.replace(/&amp;/g, '&');
    return out.trim();
  }
}
