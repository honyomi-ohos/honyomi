// 笔记编辑半模态（对齐 Mihon MangaNotesScreen / MangaNotesTextArea）：
// RichEditor WYSIWYG 编辑 + 工具栏（粗体/斜体/下划线/无序列表/有序列表/字符计数），
// 内容变化防抖自动保存（Mihon 为 0.25s 节流落库），关闭时 flush；
// 数据格式走 NotesMarkdown，与 Mihon richeditor 的 markdown 子集互通。
// 另导出 NotesDisplay：详情页简介上方按样式渲染笔记（对齐 Mihon MangaNotesSection 位置）。
import { ThemePalette } from '../../common/Theme';
import { NoteSegment, NotesMarkdown } from '../../common/NotesMarkdown';
import { AppIcon } from './AppIcon';

// 防抖自动保存间隔（毫秒）
const SAVE_DEBOUNCE_MS: number = 400;
// 正文与工具栏字号
const BODY_FONT_SIZE: number = 15;

@Component
export struct NotesSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 打开时的既有笔记（markdown），onReady 后装载进编辑器
  initialMarkdown: string = '';
  // 自动保存回调（防抖触发与关闭 flush）
  onSave: (markdown: string) => void = (_md: string) => {
  };

  // 工具栏激活态（选区：命中全部片段才亮；折叠光标：跟随预设输入样式/所在行前缀）
  @State charCount: number = 0;
  @State boldActive: boolean = false;
  @State italicActive: boolean = false;
  @State underlineActive: boolean = false;
  @State ulActive: boolean = false;
  @State olActive: boolean = false;

  // 折叠光标下的预设输入样式（setTypingStyle 生效于后续输入）
  private boldTyping: boolean = false;
  private italicTyping: boolean = false;
  private underlineTyping: boolean = false;

  private ctrl: RichEditorController = new RichEditorController();
  private loaded: boolean = false;
  private suppress: boolean = false;
  private saveTimer: number = -1;
  private lastSaved: string = '';
  // 上一次已处理内容的纯文本（onDidChange 里 diff 出单字符插入位置，识别回车）
  private prevPlain: string = '';

  aboutToDisappear(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    this.flushSave();
  }

  build() {
    Column() {
      // 工具栏（对齐 Mihon MangaNotesTextArea：加粗/斜体/下划线/列表 + 字符计数）
      Row({ space: 2 }) {
        this.textTool('B', 'bold', this.boldActive, (): void => this.toggleBold())
        this.textTool('I', 'italic', this.italicActive, (): void => this.toggleItalic())
        this.textTool('U', 'underline', this.underlineActive, (): void => this.toggleUnderline())
        Divider()
          .vertical(true)
          .height(20)
          .color(this.pal.divider)
          .margin({ left: 8, right: 8 })
        this.iconTool('format_list_bulleted', this.ulActive, (): void => this.toggleUnorderedList())
        this.iconTool('format_list_numbered', this.olActive, (): void => this.toggleOrderedList())
        Blank()
        Text(`${this.charCount}`)
          .fontSize(12)
          .fontColor(this.pal.sub)
      }
      .width('100%')
      .padding({ left: 14, right: 20, top: 4, bottom: 4 })

      Divider()
        .color(this.pal.divider)
        .margin({ left: 16, right: 16 })

      // 编辑区：内容变化防抖保存；选区/光标变化刷新工具栏
      RichEditor({ controller: this.ctrl })
        .placeholder('记录关于这部作品的备注…', { fontColor: this.pal.sub })
        .copyOptions(CopyOptions.InApp)
        .onReady(() => {
          if (!this.loaded) {
            this.loadMarkdown(this.initialMarkdown);
            this.refreshToolbar();
          }
        })
        .onSelectionChange((_range: RichEditorRange) => {
          this.refreshToolbar();
        })
        .onDidChange((_rangeBefore: TextRange, _rangeAfter: TextRange) => {
          if (this.suppress) {
            return;
          }
          // 回车续行/空列表项退出（返回 true 表示已重建处理完毕）
          if (!this.handleEnterContinuation()) {
            this.charCount = this.plainLength();
            this.scheduleSave();
          }
        })
        // 删除拦截：折叠光标紧跟列表前缀时，退格改为清除该行列表状态
        .aboutToDelete((value: RichEditorDeleteValue): boolean => {
          return this.interceptBackspace(value);
        })
        .padding({ left: 20, right: 20, top: 12, bottom: 16 })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }

  // 文本字形工具按钮（B/I/U），mode 决定自身字形，active 决定高亮
  @Builder
  textTool(label: string, mode: string, active: boolean, onTap: () => void) {
    Column() {
      Text(label)
        .fontSize(17)
        .fontWeight(mode === 'bold' ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(mode === 'italic' ? FontStyle.Italic : FontStyle.Normal)
        .decoration({
          type: mode === 'underline' ? TextDecorationType.Underline : TextDecorationType.None,
          color: active ? this.pal.primary : this.pal.sub
        })
        .fontColor(active ? this.pal.primary : this.pal.sub)
    }
    .width(38)
    .height(38)
    .justifyContent(FlexAlign.Center)
    .borderRadius(10)
    .backgroundColor(active ? this.pal.primarySoft : Color.Transparent)
    .onClick(() => {
      onTap();
    })
  }

  // 图标工具按钮（列表）
  @Builder
  iconTool(icon: string, active: boolean, onTap: () => void) {
    Column() {
      AppIcon({ name: icon, iconSize: 20, tint: active ? this.pal.primary : this.pal.sub })
    }
    .width(38)
    .height(38)
    .justifyContent(FlexAlign.Center)
    .borderRadius(10)
    .backgroundColor(active ? this.pal.primarySoft : Color.Transparent)
    .onClick(() => {
      onTap();
    })
  }

  // ---- 状态样式 ----

  // 片段 → 编辑器 span 样式（字号/颜色统一，四标志决定字形与装饰线）
  private spanStyleOf(seg: NoteSegment): RichEditorTextStyle {
    const style: RichEditorTextStyle = {
      fontColor: this.pal.text,
      fontSize: BODY_FONT_SIZE,
      fontWeight: seg.bold ? FontWeight.Bold : FontWeight.Normal,
      fontStyle: seg.italic ? FontStyle.Italic : FontStyle.Normal,
      decoration: {
        type: seg.underline ? TextDecorationType.Underline
          : (seg.strike ? TextDecorationType.LineThrough : TextDecorationType.None)
      }
    };
    return style;
  }

  // 预设输入样式（折叠光标下后续输入使用）
  private applyTypingStyle(): void {
    const style: RichEditorTextStyle = {
      fontColor: this.pal.text,
      fontSize: BODY_FONT_SIZE,
      fontWeight: this.boldTyping ? FontWeight.Bold : FontWeight.Normal,
      fontStyle: this.italicTyping ? FontStyle.Italic : FontStyle.Normal,
      decoration: {
        type: this.underlineTyping ? TextDecorationType.Underline : TextDecorationType.None
      }
    };
    this.ctrl.setTypingStyle(style);
  }

  // ---- 编辑器读写 ----

  // 读取编辑器全部文本 span → 片段序列（图片等非文本 span 跳过）
  private collectSegments(): NoteSegment[] {
    const spans: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> = this.ctrl.getSpans();
    const sorted: Array<RichEditorImageSpanResult | RichEditorTextSpanResult> =
      spans.slice().sort((a: RichEditorImageSpanResult | RichEditorTextSpanResult,
        b: RichEditorImageSpanResult | RichEditorTextSpanResult): number =>
        a.spanPosition.spanRange[0] - b.spanPosition.spanRange[0]);
    const out: NoteSegment[] = [];
    for (let i = 0; i < sorted.length; i++) {
      const ts: RichEditorTextSpanResult = sorted[i] as RichEditorTextSpanResult;
      if (typeof ts.value !== 'string' || ts.textStyle === undefined) {
        continue;
      }
      const w: number = ts.textStyle.fontWeight;
      const style: RichEditorTextStyleResult = ts.textStyle;
      const decoType: TextDecorationType = style.decoration.type;
      out.push(new NoteSegment(ts.value,
        (w >= 6 && w <= 9) || w === 11,
        style.fontStyle === FontStyle.Italic,
        decoType === TextDecorationType.Underline,
        decoType === TextDecorationType.LineThrough));
    }
    return out;
  }

  // 片段纯文本长度（字符计数）
  private plainLength(): number {
    return NotesMarkdown.plain(this.collectSegments()).length;
  }

  // 装载 markdown：清空后按解析片段逐段加 span
  private loadMarkdown(md: string): void {
    this.suppress = true;
    this.ctrl.deleteSpans();
    const segs: NoteSegment[] = NotesMarkdown.parse(md);
    for (let i = 0; i < segs.length; i++) {
      const seg: NoteSegment = segs[i];
      this.ctrl.addTextSpan(seg.text, { style: this.spanStyleOf(seg) });
    }
    this.loaded = true;
    this.lastSaved = md;
    this.suppress = false;
    this.charCount = this.plainLength();
    this.prevPlain = NotesMarkdown.plain(segs);
  }

  // 当前内容的 markdown（未装载完成时返回上次保存值）
  private currentMarkdown(): string {
    if (this.suppress || !this.loaded) {
      return this.lastSaved;
    }
    return NotesMarkdown.serialize(NotesMarkdown.merge(this.collectSegments()));
  }

  // ---- 自动保存 ----

  private scheduleSave(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.flushSave();
    }, SAVE_DEBOUNCE_MS);
  }

  // 立即保存（内容有变化才回调）
  private flushSave(): void {
    if (!this.loaded) {
      return;
    }
    const md: string = this.currentMarkdown();
    if (md !== this.lastSaved) {
      this.lastSaved = md;
      this.onSave(md);
    }
  }

  // ---- 工具栏状态 ----

  // 刷新工具栏：选区取选内片段样式；折叠光标取预设输入样式；列表取锚点行前缀
  private refreshToolbar(): void {
    if (this.suppress || !this.loaded) {
      return;
    }
    const sel: RichEditorSelection = this.ctrl.getSelection();
    const start: number = sel.selection[0];
    const end: number = sel.selection[1];
    if (end > start) {
      const segs: NoteSegment[] = this.segmentsInRange(start, end);
      this.boldActive = this.allHave(segs, 'bold');
      this.italicActive = this.allHave(segs, 'italic');
      this.underlineActive = this.allHave(segs, 'underline');
    } else {
      this.syncTypingFromContext();
      this.boldActive = this.boldTyping;
      this.italicActive = this.italicTyping;
      this.underlineActive = this.underlineTyping;
    }
    const anchor: number = end > start ? end - 1 : end;
    const lineText: string = this.lineTextAt(anchor);
    this.ulActive = /^[ \t]*• /.test(lineText);
    this.olActive = /^[ \t]*\d+\. /.test(lineText);
  }

  // 折叠光标：由光标前字符样式同步预设输入样式（样式变化才重设）
  private syncTypingFromContext(): void {
    const caret: number = this.ctrl.getCaretOffset();
    const segs: NoteSegment[] = caret > 0 ? this.segmentsInRange(caret - 1, caret) : [];
    const seg: NoteSegment | undefined = segs.length > 0 ? segs[segs.length - 1] : undefined;
    const bold: boolean = seg !== undefined && seg.bold;
    const italic: boolean = seg !== undefined && seg.italic;
    const underline: boolean = seg !== undefined && seg.underline;
    if (bold !== this.boldTyping || italic !== this.italicTyping || underline !== this.underlineTyping) {
      this.boldTyping = bold;
      this.italicTyping = italic;
      this.underlineTyping = underline;
      this.applyTypingStyle();
    }
  }

  // [start, end) 内的片段（跨片段按区间裁剪）
  private segmentsInRange(start: number, end: number): NoteSegment[] {
    const all: NoteSegment[] = this.collectSegments();
    const out: NoteSegment[] = [];
    let pos: number = 0;
    for (let i = 0; i < all.length; i++) {
      const seg: NoteSegment = all[i];
      const s: number = pos;
      const e: number = pos + seg.text.length;
      pos = e;
      if (e <= start || s >= end) {
        continue;
      }
      const from: number = Math.max(s, start);
      const to: number = Math.min(e, end);
      out.push(new NoteSegment(seg.text.substring(from - s, to - s), seg.bold, seg.italic, seg.underline, seg.strike));
    }
    return out;
  }

  // offset 所在行的文本（换行为行界）
  private lineTextAt(offset: number): string {
    const full: string = NotesMarkdown.plain(this.collectSegments());
    if (full === '') {
      return '';
    }
    const from: number = Math.min(offset, full.length - 1);
    const start: number = full.lastIndexOf('\n', from) + 1;
    let end: number = full.indexOf('\n', start);
    if (end < 0) {
      end = full.length;
    }
    return full.substring(start, end);
  }

  // 选内片段是否全部带某样式（空集合视为否）
  private allHave(segs: NoteSegment[], kind: string): boolean {
    if (segs.length === 0) {
      return false;
    }
    for (let i = 0; i < segs.length; i++) {
      const seg: NoteSegment = segs[i];
      if (seg.text === '') {
        continue;
      }
      if (kind === 'bold' && !seg.bold) {
        return false;
      }
      if (kind === 'italic' && !seg.italic) {
        return false;
      }
      if (kind === 'underline' && !seg.underline) {
        return false;
      }
    }
    return true;
  }

  // ---- 样式切换 ----

  private toggleBold(): void {
    this.toggleTextStyle('bold');
  }

  private toggleItalic(): void {
    this.toggleTextStyle('italic');
  }

  private toggleUnderline(): void {
    this.toggleTextStyle('underline');
  }

  // 选区：updateSpanStyle 整段切换；折叠光标：切换预设输入样式
  private toggleTextStyle(kind: string): void {
    if (!this.loaded || this.suppress) {
      return;
    }
    const sel: RichEditorSelection = this.ctrl.getSelection();
    const start: number = sel.selection[0];
    const end: number = sel.selection[1];
    if (end > start) {
      const segs: NoteSegment[] = this.segmentsInRange(start, end);
      const target: boolean = !this.allHave(segs, kind);
      const style: RichEditorTextStyle = {};
      if (kind === 'bold') {
        style.fontWeight = target ? FontWeight.Bold : FontWeight.Normal;
      } else if (kind === 'italic') {
        style.fontStyle = target ? FontStyle.Italic : FontStyle.Normal;
      } else {
        style.decoration = {
          type: target ? TextDecorationType.Underline : TextDecorationType.None
        };
      }
      this.ctrl.updateSpanStyle({ start: start, end: end, textStyle: style });
      this.refreshToolbar();
      this.scheduleSave();
    } else {
      if (kind === 'bold') {
        this.boldTyping = !this.boldTyping;
      } else if (kind === 'italic') {
        this.italicTyping = !this.italicTyping;
      } else {
        this.underlineTyping = !this.underlineTyping;
      }
      this.applyTypingStyle();
      this.boldActive = this.boldTyping;
      this.italicActive = this.italicTyping;
      this.underlineActive = this.underlineTyping;
    }
  }

  // ---- 列表切换 ----

  private toggleUnorderedList(): void {
    this.toggleList(false);
  }

  private toggleOrderedList(): void {
    this.toggleList(true);
  }

  // 列表切换（对齐 Mihon richeditor 行为）：受影响行 = 与选区/光标相交的行；
  // 全部已有目标前缀则移除，否则添加（有序列表按受影响行顺序重新编号）；
  // 实现为全量重建（拆行 → 改前缀 → deleteSpans + addTextSpan），并恢复光标。
  private toggleList(ordered: boolean): void {
    if (!this.loaded || this.suppress) {
      return;
    }
    const merged: NoteSegment[] = NotesMarkdown.merge(this.collectSegments());
    const full: string = NotesMarkdown.plain(merged);
    const sel: RichEditorSelection = this.ctrl.getSelection();
    const selStart: number = sel.selection[0];
    const selEnd: number = sel.selection[1];
    const affectEnd: number = selEnd > selStart ? selEnd : selStart + 1;

    // 拆行并记录每行起始偏移
    const lines: NoteSegment[][] = [];
    const lineStarts: number[] = [];
    let cur: NoteSegment[] = [];
    let pos: number = 0;
    let lineStart: number = 0;
    for (let i = 0; i < merged.length; i++) {
      const seg: NoteSegment = merged[i];
      if (!seg.text.includes('\n')) {
        cur.push(seg);
        pos += seg.text.length;
        continue;
      }
      const parts: string[] = seg.text.split('\n');
      for (let j = 0; j < parts.length; j++) {
        if (j > 0) {
          lines.push(cur);
          lineStarts.push(lineStart);
          pos += 1;
          lineStart = pos;
          cur = [];
        }
        if (parts[j] !== '') {
          cur.push(new NoteSegment(parts[j], seg.bold, seg.italic, seg.underline, seg.strike));
        }
        pos += parts[j].length;
      }
    }
    lines.push(cur);
    lineStarts.push(lineStart);

    // 受影响行与目标态
    const affected: boolean[] = [];
    let anyAffected: boolean = false;
    let allHaveTarget: boolean = true;
    for (let li = 0; li < lines.length; li++) {
      const lineText: string = NotesMarkdown.plain(lines[li]);
      const lineEnd: number = lineStarts[li] + lineText.length;
      const hit: boolean = lineEnd >= selStart && lineStarts[li] < affectEnd;
      affected.push(hit);
      if (hit) {
        anyAffected = true;
        const has: boolean = ordered ? /^[ \t]*\d+\. /.test(lineText) : /^[ \t]*• /.test(lineText);
        if (!has) {
          allHaveTarget = false;
        }
      }
    }
    if (!anyAffected) {
      return;
    }
    const target: boolean = !allHaveTarget;

    // 逐行重建：未受影响行原样；受影响行按目标态改前缀，同时换算新光标
    const outSegs: NoteSegment[] = [];
    let counter: number = 0;
    let newCaret: number = -1;
    for (let li = 0; li < lines.length; li++) {
      if (li > 0) {
        outSegs.push(new NoteSegment('\n', false, false, false, false));
      }
      const lineText: string = NotesMarkdown.plain(lines[li]);
      if (!affected[li]) {
        for (let k = 0; k < lines[li].length; k++) {
          outSegs.push(lines[li][k]);
        }
        continue;
      }
      const um: RegExpMatchArray | null = lineText.match(/^([ \t]*)• /);
      const om: RegExpMatchArray | null = lineText.match(/^[ \t]*\d+\. /);
      let oldPrefixLen: number = 0;
      if (um !== null) {
        oldPrefixLen = um[0].length;
      } else if (om !== null) {
        oldPrefixLen = om[0].length;
      }
      let newPrefix: string = '';
      if (ordered) {
        if (target) {
          counter += 1;
          newPrefix = `${counter}. `;
        } else {
          counter = 0;
        }
      } else {
        if (target) {
          newPrefix = '• ';
        }
      }
      // 光标换算：光标在本行内 → 前缀后按原列位映射；本行整体在光标前 → 平移
      const lineStartOff: number = lineStarts[li];
      const lineEndOff: number = lineStartOff + lineText.length;
      const anchor: number = selEnd > selStart ? selEnd : selEnd;
      if (selEnd >= lineStartOff && selEnd <= lineEndOff) {
        newCaret = lineStartOff + newPrefix.length +
          Math.max(0, anchor - lineStartOff - oldPrefixLen);
      } else if (lineEndOff < selEnd) {
        if (newCaret < 0) {
          newCaret = selEnd;
        }
        newCaret += newPrefix.length - oldPrefixLen;
      }
      if (newPrefix !== '') {
        outSegs.push(new NoteSegment(newPrefix, false, false, false, false));
      }
      // 去掉旧前缀后的行内容
      let pos2: number = 0;
      for (let k = 0; k < lines[li].length; k++) {
        const seg: NoteSegment = lines[li][k];
        const s2: number = pos2;
        const e2: number = pos2 + seg.text.length;
        pos2 = e2;
        if (e2 <= oldPrefixLen) {
          continue;
        }
        const from: number = Math.max(s2, oldPrefixLen);
        const piece: string = seg.text.substring(from - s2, e2 - s2);
        if (piece !== '') {
          outSegs.push(new NoteSegment(piece, seg.bold, seg.italic, seg.underline, seg.strike));
        }
      }
    }

    // 全量重建编辑器并恢复光标
    this.rebuildEditor(outSegs, newCaret);
  }

  // ---- 列表回车续行 / 退格清除 ----

  // 单字符插入位置：cur 比 prev 恰好多一个字符且删除该字符后与 prev 相同，返回插入位置；否则 -1
  private singleInsertPos(prev: string, cur: string): number {
    if (cur.length !== prev.length + 1) {
      return -1;
    }
    let i: number = 0;
    while (i < prev.length && prev.charAt(i) === cur.charAt(i)) {
      i++;
    }
    if (cur.substring(i + 1) === prev.substring(i)) {
      return i;
    }
    return -1;
  }

  // 移除 [start, end) 区间的文本（片段级裁剪，保留样式）
  private segmentsWithoutRange(segs: NoteSegment[], start: number, end: number): NoteSegment[] {
    const out: NoteSegment[] = [];
    let pos: number = 0;
    for (let i = 0; i < segs.length; i++) {
      const seg: NoteSegment = segs[i];
      const s: number = pos;
      const e: number = pos + seg.text.length;
      pos = e;
      if (e <= start) {
        out.push(seg);
        continue;
      }
      if (s >= end) {
        out.push(seg);
        continue;
      }
      if (s < start) {
        out.push(new NoteSegment(seg.text.substring(0, start - s), seg.bold, seg.italic, seg.underline, seg.strike));
      }
      if (e > end) {
        out.push(new NoteSegment(seg.text.substring(end - s), seg.bold, seg.italic, seg.underline, seg.strike));
      }
    }
    return out;
  }

  // 在 offset 处插入无样式文本（片段级切分，保留前后样式）
  private withInsertAt(segs: NoteSegment[], offset: number, text: string): NoteSegment[] {
    const out: NoteSegment[] = [];
    let pos: number = 0;
    let inserted: boolean = false;
    for (let i = 0; i < segs.length; i++) {
      const seg: NoteSegment = segs[i];
      const s: number = pos;
      const e: number = pos + seg.text.length;
      pos = e;
      if (!inserted && s >= offset) {
        out.push(new NoteSegment(text, false, false, false, false));
        inserted = true;
      }
      if (e <= offset || s >= offset) {
        out.push(seg);
        continue;
      }
      // s < offset < e：切分片段后插入
      out.push(new NoteSegment(seg.text.substring(0, offset - s), seg.bold, seg.italic, seg.underline, seg.strike));
      if (!inserted) {
        out.push(new NoteSegment(text, false, false, false, false));
        inserted = true;
      }
      out.push(new NoteSegment(seg.text.substring(offset - s), seg.bold, seg.italic, seg.underline, seg.strike));
    }
    if (!inserted) {
      out.push(new NoteSegment(text, false, false, false, false));
    }
    return out;
  }

  // 从 fromOffset 起对后续连续有序列表行顺延重编号（起始值 startNum，遇非有序行停止）
  private renumberOlAfter(segs: NoteSegment[], fromOffset: number, startNum: number): NoteSegment[] {
    let working: NoteSegment[] = segs;
    let lineStart: number = fromOffset;
    let num: number = startNum;
    for (let guard: number = 0; guard < 500; guard++) {
      const full: string = NotesMarkdown.plain(working);
      if (lineStart >= full.length) {
        break;
      }
      let lineEnd: number = full.indexOf('\n', lineStart);
      const hasTerminator: boolean = lineEnd >= 0;
      if (!hasTerminator) {
        lineEnd = full.length;
      }
      const lineText: string = full.substring(lineStart, lineEnd);
      const om: RegExpMatchArray | null = lineText.match(/^([ \t]*)(\d+)\. /);
      if (om === null) {
        break;
      }
      const digitStart: number = lineStart + om[1].length;
      const digitLen: number = om[2].length;
      const repl: string = `${num}`;
      working = this.segmentsWithoutRange(working, digitStart, digitStart + digitLen);
      working = this.withInsertAt(working, digitStart, repl);
      num += 1;
      if (!hasTerminator) {
        break;
      }
      lineStart = lineEnd - digitLen + repl.length + 1;
    }
    return working;
  }

  // 全量重建编辑器内容并恢复光标（程序化变更统一入口：suppress 包裹，同步 prevPlain/计数/工具栏/保存）
  private rebuildEditor(segs: NoteSegment[], caret: number): void {
    this.suppress = true;
    this.ctrl.deleteSpans();
    const finalSegs: NoteSegment[] = NotesMarkdown.merge(segs);
    for (let i = 0; i < finalSegs.length; i++) {
      const seg: NoteSegment = finalSegs[i];
      this.ctrl.addTextSpan(seg.text, { style: this.spanStyleOf(seg) });
    }
    const plain: string = NotesMarkdown.plain(finalSegs);
    if (caret >= 0) {
      this.ctrl.setCaretOffset(Math.min(caret, plain.length));
    }
    this.suppress = false;
    this.prevPlain = plain;
    this.charCount = plain.length;
    this.refreshToolbar();
    this.scheduleSave();
  }

  // 回车续行（onDidChange 内调用）：识别单字符 '\n' 插入，
  // 空列表项回车退出列表，非空列表项回车在下一行续接前缀（有序列表顺延重编后续行）。
  // 返回 true 表示已重建处理完毕，调用方跳过默认计数/保存。
  private handleEnterContinuation(): boolean {
    if (!this.loaded) {
      return false;
    }
    const merged: NoteSegment[] = NotesMarkdown.merge(this.collectSegments());
    const cur: string = NotesMarkdown.plain(merged);
    const prev: string = this.prevPlain;
    const p: number = this.singleInsertPos(prev, cur);
    if (p < 0 || cur.substring(p, p + 1) !== '\n') {
      this.prevPlain = cur;
      return false;
    }
    // 按回车前文本计算被切分行
    let lineStart: number = 0;
    if (p > 0) {
      lineStart = prev.lastIndexOf('\n', p - 1) + 1;
    }
    let lineEnd: number = prev.indexOf('\n', lineStart);
    if (lineEnd < 0) {
      lineEnd = prev.length;
    }
    const beforeCaret: string = prev.substring(lineStart, p);
    const afterCaret: string = prev.substring(p, lineEnd);
    const um: RegExpMatchArray | null = beforeCaret.match(/^([ \t]*)• /);
    const om: RegExpMatchArray | null = um === null ? beforeCaret.match(/^([ \t]*)(\d+)\. /) : null;
    let lead: string = '';
    let prefixLen: number = 0;
    if (um !== null) {
      lead = um[1];
      prefixLen = um[0].length;
    } else if (om !== null) {
      lead = om[1];
      prefixLen = om[0].length;
    }
    if (prefixLen === 0) {
      this.prevPlain = cur;
      return false;
    }
    // 空列表项回车：移除前缀 + 刚插入的换行，留普通空行，光标回行首
    if (afterCaret === '' && beforeCaret.length === prefixLen) {
      const segs: NoteSegment[] = this.segmentsWithoutRange(merged, lineStart, p + 1);
      this.rebuildEditor(segs, lineStart);
      return true;
    }
    // 非空列表项回车：新行续接列表前缀
    let insertText: string = '';
    let olNum: number = -1;
    if (um !== null) {
      insertText = `${lead}• `;
    } else if (om !== null) {
      olNum = parseInt(om[2], 10);
      insertText = `${lead}${olNum + 1}. `;
    }
    let segs: NoteSegment[] = this.withInsertAt(merged, p + 1, insertText);
    const newCaret: number = p + 1 + insertText.length;
    // 有序列表：后续连续有序行顺延重编
    if (olNum >= 0 && lineEnd < prev.length) {
      const nextLineStart: number = p + 1 + insertText.length + afterCaret.length + 1;
      segs = this.renumberOlAfter(segs, nextLineStart, olNum + 2);
    }
    this.rebuildEditor(segs, newCaret);
    return true;
  }

  // 退格拦截（aboutToDelete 内调用）：折叠光标紧跟列表前缀时，
  // 取消本次删除，改为移除该行前缀（退出列表状态），光标回行首；其余情况放行默认删除。
  private interceptBackspace(value: RichEditorDeleteValue): boolean {
    if (!this.loaded || this.suppress) {
      return true;
    }
    if (value.direction !== RichEditorDeleteDirection.BACKWARD) {
      return true;
    }
    const sel: RichEditorSelection = this.ctrl.getSelection();
    const start: number = sel.selection[0];
    const end: number = sel.selection[1];
    if (end !== start) {
      return true;
    }
    const caret: number = start;
    const merged: NoteSegment[] = NotesMarkdown.merge(this.collectSegments());
    const full: string = NotesMarkdown.plain(merged);
    let lineStart: number = 0;
    if (caret > 0) {
      lineStart = full.lastIndexOf('\n', caret - 1) + 1;
    }
    let lineEnd: number = full.indexOf('\n', lineStart);
    if (lineEnd < 0) {
      lineEnd = full.length;
    }
    const lineText: string = full.substring(lineStart, lineEnd);
    const um: RegExpMatchArray | null = lineText.match(/^([ \t]*)• /);
    const om: RegExpMatchArray | null = um === null ? lineText.match(/^([ \t]*)(\d+)\. /) : null;
    let prefixLen: number = 0;
    if (um !== null) {
      prefixLen = um[0].length;
    } else if (om !== null) {
      prefixLen = om[0].length;
    }
    if (prefixLen === 0) {
      return true;
    }
    if (caret !== lineStart + prefixLen) {
      return true;
    }
    // 拦截：下一拍移除前缀（内容校验未变才执行）
    setTimeout(() => {
      if (!this.loaded || this.suppress) {
        return;
      }
      const m2: NoteSegment[] = NotesMarkdown.merge(this.collectSegments());
      if (NotesMarkdown.plain(m2) !== full) {
        return;
      }
      const segs: NoteSegment[] = this.segmentsWithoutRange(m2, lineStart, lineStart + prefixLen);
      this.rebuildEditor(segs, lineStart);
    }, 0);
    return false;
  }
}

// 笔记展示（对齐 Mihon MangaNotesDisplay）：markdown → 带样式 Span 渲染，
// 列表前缀以字面文本展示（"• " / "N. "）
@Component
export struct NotesDisplay {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  markdown: string = '';

  build() {
    Text() {
      ForEach(NotesMarkdown.parse(this.markdown), (seg: NoteSegment, idx: number) => {
        Span(seg.text)
          .fontWeight(seg.bold ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(seg.italic ? FontStyle.Italic : FontStyle.Normal)
          .decoration({
            type: seg.underline ? TextDecorationType.Underline
              : (seg.strike ? TextDecorationType.LineThrough : TextDecorationType.None)
          })
      }, (seg: NoteSegment, idx: number) =>
        `${idx}-${seg.bold ? 1 : 0}${seg.italic ? 1 : 0}${seg.underline ? 1 : 0}${seg.strike ? 1 : 0}-${seg.text}`)
    }
    .fontSize(14)
    .fontColor(this.pal.text)
    .width('100%')
  }
}
