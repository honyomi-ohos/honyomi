// 标题相似度评分（意图匹配共用）：用户口述的作品名与库内标题做模糊匹配
export class TitleMatch {
  // 归一化小写比较：完全相等 > 前缀 > 包含 > 分词重叠
  static score(query: string, title: string): number {
    const q: string = query.toLowerCase().trim();
    const t: string = title.toLowerCase().trim();
    if (q === '' || t === '') {
      return 0;
    }
    if (t === q) {
      return 1000;
    }
    const lenDiff: number = Math.abs(t.length - q.length);
    if (t.startsWith(q) || q.startsWith(t)) {
      return 800 - lenDiff;
    }
    if (t.includes(q) || q.includes(t)) {
      return 600 - lenDiff;
    }
    const tokens: string[] = q.split(/[\s:：·・\-—,，、.。!！?？]+/);
    let overlap: number = 0;
    for (const tok of tokens) {
      if (tok.length > 0 && t.includes(tok)) {
        overlap++;
      }
    }
    return overlap > 0 ? 200 + overlap * 50 : 0;
  }
}
