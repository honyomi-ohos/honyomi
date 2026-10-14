// 自然排序比较（对齐 Mihon 无此能力，为其补充）：
// 数字段按数值比较（"第10话" > "第9话"），中文数字（"第十章" > "第二章"）按解析值比较，
// 纯中文数字串（"二零二四"）按位值解析；其余字符忽略大小写逐字符比较。
// 本地源目录扫描与详情页"按名称"排序共用。
export class NaturalCompare {
  private static readonly ASCII_DIGITS: string = '0123456789';
  private static readonly FW_DIGITS: string = '０１２３４５６７８９';
  // 中文数字字符（含大写体）：值 0-9（两 = 2）
  private static readonly CN_DIGIT_CHARS: string = '零〇一二两三四五六七八九壹贰叁肆伍陆柒捌玖';
  // 中文数量级单位：十/百/千 与 万/亿
  private static readonly CN_SMALL_UNITS: string = '十拾百佰千仟';
  private static readonly CN_SMALL_VALUES: number[] = [10, 10, 100, 100, 1000, 1000];
  private static readonly CN_DIGIT_VALUES: number[] = [0, 0, 1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 4, 5, 6, 7, 8, 9];

  // 0-9 返回数字值；全角数字一并识别；非数字返回 -1
  static digitValue(c: string): number {
    const ascii = NaturalCompare.ASCII_DIGITS.indexOf(c);
    if (ascii >= 0) {
      return ascii;
    }
    const fw = NaturalCompare.FW_DIGITS.indexOf(c);
    if (fw >= 0) {
      return fw;
    }
    const cn = NaturalCompare.CN_DIGIT_CHARS.indexOf(c);
    if (cn >= 0) {
      return NaturalCompare.CN_DIGIT_VALUES[cn];
    }
    return -1;
  }

  private static smallUnitValue(c: string): number {
    const idx = NaturalCompare.CN_SMALL_UNITS.indexOf(c);
    return idx >= 0 ? NaturalCompare.CN_SMALL_VALUES[idx] : -1;
  }

  private static isWan(c: string): boolean {
    return c === '万' || c === '萬';
  }

  private static isYi(c: string): boolean {
    return c === '亿' || c === '億';
  }

  // 中文（或混合阿拉伯）数字串转数值：
  // 含数量级单位时按单位算法（"一百二十三"→123，"十二"→12，"一万二"→12000）；
  // 纯数字字符时按十进制位值（"二三"→23，"二零二四"→2024）
  static parseNumberRun(s: string): number {
    let hasUnit = false;
    let onlyDigits = true;
    for (let i = 0; i < s.length; i++) {
      const c = s.charAt(i);
      if (NaturalCompare.smallUnitValue(c) > 0 || NaturalCompare.isWan(c) || NaturalCompare.isYi(c)) {
        hasUnit = true;
        onlyDigits = false;
      } else if (NaturalCompare.digitValue(c) < 0) {
        onlyDigits = false;
      }
    }
    if (onlyDigits) {
      let value = 0;
      for (let i = 0; i < s.length; i++) {
        value = value * 10 + NaturalCompare.digitValue(s.charAt(i));
      }
      return value;
    }
    if (!hasUnit) {
      // 混合但无单位：按位值拼接（如全角+半角混排）
      let value = 0;
      let any = false;
      for (let i = 0; i < s.length; i++) {
        const d = NaturalCompare.digitValue(s.charAt(i));
        if (d >= 0) {
          value = value * 10 + d;
          any = true;
        }
      }
      return any ? value : 0;
    }
    // 单位算法：段内累计（个/十/百/千），遇万/亿进段
    let total = 0;
    let section = 0;
    let digit = -1;
    for (let i = 0; i < s.length; i++) {
      const c = s.charAt(i);
      const d = NaturalCompare.digitValue(c);
      if (d >= 0) {
        digit = d;
        continue;
      }
      const scale = NaturalCompare.smallUnitValue(c);
      if (scale > 0) {
        if (digit < 0) {
          digit = 1; // "十"开头的"十二"
        }
        section += digit * scale;
        digit = -1;
        continue;
      }
      if (NaturalCompare.isWan(c)) {
        if (digit >= 0) {
          section += digit;
          digit = -1;
        }
        section *= 10000;
        total += section;
        section = 0;
        continue;
      }
      if (NaturalCompare.isYi(c)) {
        if (digit >= 0) {
          section += digit;
          digit = -1;
        }
        total = (total + section) * 100000000;
        section = 0;
      }
    }
    if (digit >= 0) {
      section += digit;
    }
    return total + section;
  }

  private static isNumericChar(c: string): boolean {
    if (NaturalCompare.digitValue(c) >= 0) {
      return true;
    }
    return NaturalCompare.smallUnitValue(c) > 0 || NaturalCompare.isWan(c) || NaturalCompare.isYi(c);
  }

  // 从 start 起读取连续数字性字符段，返回 { text, end }（end 为段后首个非数字字符下标）
  private static readRun(s: string, start: number): NaturalRun {
    let end = start;
    while (end < s.length && NaturalCompare.isNumericChar(s.charAt(end))) {
      end += 1;
    }
    const run = new NaturalRun();
    run.text = s.substring(start, end);
    run.end = end;
    return run;
  }

  // 自然比较：返回负/零/正。数字段按数值，其余字符忽略大小写逐字符比较
  static compare(a: string, b: string): number {
    let ia = 0;
    let ib = 0;
    while (ia < a.length && ib < b.length) {
      const ca = a.charAt(ia);
      const cb = b.charAt(ib);
      const aNum = NaturalCompare.isNumericChar(ca);
      const bNum = NaturalCompare.isNumericChar(cb);
      if (aNum && bNum) {
        const ra = NaturalCompare.readRun(a, ia);
        const rb = NaturalCompare.readRun(b, ib);
        // 段内字符完全一致时跳过解析直接前进（保留 "01" 与 "1" 的稳定序）
        if (ra.text !== rb.text) {
          const va = NaturalCompare.parseNumberRun(ra.text);
          const vb = NaturalCompare.parseNumberRun(rb.text);
          if (va !== vb) {
            return va < vb ? -1 : 1;
          }
        }
        ia = ra.end;
        ib = rb.end;
        continue;
      }
      const na = ca.toLowerCase();
      const nb = cb.toLowerCase();
      if (na !== nb) {
        return na < nb ? -1 : 1;
      }
      ia += 1;
      ib += 1;
    }
    const remA = a.length - ia;
    const remB = b.length - ib;
    if (remA !== remB) {
      return remA < remB ? -1 : 1;
    }
    return 0;
  }

  // 便捷排序：返回已排序的新数组
  static sorted(list: string[]): string[] {
    const copy = list.slice();
    copy.sort((a: string, b: string): number => NaturalCompare.compare(a, b));
    return copy;
  }
}

class NaturalRun {
  text: string = '';
  end: number = 0;
}
