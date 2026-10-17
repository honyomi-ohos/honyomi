// 应用支持的语言注册表：tag 为 BCP-47 标签（存储/切换用），nativeName 为该语言的自称（不随界面语言变化）
export class AppLanguage {
  readonly tag: string;
  readonly nativeName: string;

  constructor(tag: string, nativeName: string) {
    this.tag = tag;
    this.nativeName = nativeName;
  }
}

export class Languages {
  static all(): AppLanguage[] {
    const list: AppLanguage[] = [
      new AppLanguage('zh-Hans', '简体中文'),
      new AppLanguage('zh-Hant-TW', '繁體中文'),
      new AppLanguage('en-US', 'English'),
      new AppLanguage('ja-JP', '日本語'),
      new AppLanguage('ko-KR', '한국어'),
      new AppLanguage('es-ES', 'Español'),
      new AppLanguage('pt-BR', 'Português (Brasil)'),
      new AppLanguage('fr-FR', 'Français'),
      new AppLanguage('de-DE', 'Deutsch'),
      new AppLanguage('ru-RU', 'Русский'),
      new AppLanguage('vi-VN', 'Tiếng Việt'),
      new AppLanguage('id-ID', 'Bahasa Indonesia'),
      new AppLanguage('th', 'ไทย'),
      new AppLanguage('ar', 'العربية'),
      new AppLanguage('tr', 'Türkçe'),
      new AppLanguage('it', 'Italiano'),
      new AppLanguage('pl', 'Polski'),
      new AppLanguage('uk', 'Українська'),
      new AppLanguage('ms', 'Bahasa Melayu'),
      new AppLanguage('fil', 'Filipino'),
    ];
    return list;
  }

  static findByTag(tag: string): AppLanguage | undefined {
    const list: AppLanguage[] = Languages.all();
    for (const lang of list) {
      if (lang.tag === tag) {
        return lang;
      }
    }
    return undefined;
  }

  static displayName(tag: string): string {
    const lang: AppLanguage | undefined = Languages.findByTag(tag);
    if (lang === undefined) {
      return tag;
    }
    return lang.nativeName;
  }
}
