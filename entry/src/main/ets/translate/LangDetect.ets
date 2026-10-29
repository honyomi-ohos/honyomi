// 内容语言检测：按 Unicode 文字区段统计文本主导语言，
// 供翻译前「当前语言 vs 目标语言」一致性判断（一致则跳过翻译）。
// 可判定：日文（假名）/ 韩文（谚文）/ 中文简繁（汉字 + 简繁特征字）/ 俄文（西里尔）；
// 拉丁字母语族（英/法/德/西/葡/意等）无法按文字区段区分，返回空串（未知不拦截翻译）。
export class LangDetect {
  // 简繁特征字对照（同下标互为简繁体）：汉字文本中计数多者判定中文简/繁
  private static readonly SIMP_CHARS: string = '们这说对时里个为发长东门问过学读电车网语历体点经开关';
  private static readonly TRAD_CHARS: string = '們這說對時裡個為發長東門問過學讀電車網語歷體點經開關';

  // 检测文本主导语言，返回应用内语言码（zh/zh-Hant/ja/ko/ru）；无法判定返回空串
  static detect(text: string): string {
    let kana: number = 0;
    let hangul: number = 0;
    let han: number = 0;
    let cyrillic: number = 0;
    let simp: number = 0;
    let trad: number = 0;
    for (let i = 0; i < text.length; i++) {
      const c: number = text.charCodeAt(i);
      // 平假名/片假名（含半角片假名）
      if ((c >= 0x3040 && c <= 0x30FF) || (c >= 0xFF66 && c <= 0xFF9D)) {
        kana++;
        continue;
      }
      // 谚文（音节块 + 谚文字母）
      if ((c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x1100 && c <= 0x11FF)) {
        hangul++;
        continue;
      }
      // 汉字（扩展A + 基本区 + 兼容区）
      if ((c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0xF900 && c <= 0xFAFF)) {
        han++;
        const ch: string = text.charAt(i);
        if (LangDetect.SIMP_CHARS.indexOf(ch) >= 0) {
          simp++;
        }
        if (LangDetect.TRAD_CHARS.indexOf(ch) >= 0) {
          trad++;
        }
        continue;
      }
      // 西里尔字母
      if (c >= 0x0400 && c <= 0x04FF) {
        cyrillic++;
        continue;
      }
    }
    // 有假名即为日文（中文/韩文不含假名，优先级最高）
    if (kana > 0) {
      return 'ja';
    }
    if (hangul > 0) {
      return 'ko';
    }
    if (han > 0) {
      if (simp > trad) {
        return 'zh';
      }
      if (trad > simp) {
        return 'zh-Hant';
      }
      // 简繁无法判定（如纯汉字日文/无特征字文本）：视为未知，不拦截
      return '';
    }
    if (cyrillic > 0) {
      return 'ru';
    }
    return '';
  }

  // 内容语言与目标语言是否一致（一致则无需翻译；未知语言不拦截）
  static sameLang(text: string, target: string): boolean {
    const lang: string = LangDetect.detect(text);
    return lang !== '' && lang === target;
  }
}
