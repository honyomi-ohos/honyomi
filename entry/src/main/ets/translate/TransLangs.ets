// 翻译语言注册表：应用内统一语言码（BCP-47 风格小写基底 + 区域后缀），
// 各引擎实现自行映射到自家语言码；目标语言选择器选项来源
export interface TransLang {
  // 应用内语言码（持久化值，跨引擎通用）
  code: string;
  // 原生名（语言选择器惯例：不随应用界面语言切换）
  label: string;
}

export class TransLangs {
  // 目标语言候选（设置页选择器展示顺序）
  static readonly TARGETS: TransLang[] = [
    { code: 'zh', label: '简体中文' },
    { code: 'zh-Hant', label: '繁體中文' },
    { code: 'en', label: 'English' },
    { code: 'ja', label: '日本語' },
    { code: 'ko', label: '한국어' },
    { code: 'fr', label: 'Français' },
    { code: 'de', label: 'Deutsch' },
    { code: 'es', label: 'Español' },
    { code: 'ru', label: 'Русский' },
    { code: 'pt', label: 'Português' },
    { code: 'it', label: 'Italiano' }
  ];

  // 语言码 → 原生名（未知码原样返回）
  static labelOf(code: string): string {
    for (const lang of TransLangs.TARGETS) {
      if (lang.code === code) {
        return lang.label;
      }
    }
    return code;
  }

  // 语言码在候选表中的下标（未找到返回 -1，选择器回显用）
  static indexOf(code: string): number {
    for (let i = 0; i < TransLangs.TARGETS.length; i++) {
      if (TransLangs.TARGETS[i].code === code) {
        return i;
      }
    }
    return -1;
  }
}
