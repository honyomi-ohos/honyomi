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
      new AppLanguage('am', 'አማርኛ'),
      new AppLanguage('ar', 'العربية'),
      new AppLanguage('as', 'অসমীয়া'),
      new AppLanguage('az', 'Azərbaycan'),
      new AppLanguage('be', 'Беларуская'),
      new AppLanguage('bg', 'Български'),
      new AppLanguage('bn', 'বাংলা'),
      new AppLanguage('ca', 'Català'),
      new AppLanguage('ceb', 'Cebuano'),
      new AppLanguage('cs', 'Čeština'),
      new AppLanguage('cv', 'Чӑваш'),
      new AppLanguage('da', 'Dansk'),
      new AppLanguage('el', 'Ελληνικά'),
      new AppLanguage('eo', 'Esperanto'),
      new AppLanguage('eu', 'Euskara'),
      new AppLanguage('fa', 'فارسی'),
      new AppLanguage('fi', 'Suomi'),
      new AppLanguage('fil', 'Filipino'),
      new AppLanguage('gl', 'Galego'),
      new AppLanguage('he', 'עברית'),
      new AppLanguage('hi', 'हिन्दी'),
      new AppLanguage('hr', 'Hrvatski'),
      new AppLanguage('hu', 'Magyar'),
      new AppLanguage('it', 'Italiano'),
      new AppLanguage('jv', 'Basa Jawa'),
      new AppLanguage('ka-GE', 'ქართული'),
      new AppLanguage('kk', 'Қазақша'),
      new AppLanguage('km', 'ភាសាខ្មែរ'),
      new AppLanguage('kmr', 'Kurmancî'),
      new AppLanguage('kn', 'ಕನ್ನಡ'),
      new AppLanguage('lt', 'Lietuvių'),
      new AppLanguage('lv', 'Latviešu'),
      new AppLanguage('ml', 'മലയാളം'),
      new AppLanguage('mr', 'मराठी'),
      new AppLanguage('ms', 'Bahasa Melayu'),
      new AppLanguage('my', 'မြန်မာ'),
      new AppLanguage('nb-NO', 'Norsk bokmål'),
      new AppLanguage('ne', 'नेपाली'),
      new AppLanguage('nl', 'Nederlands'),
      new AppLanguage('nn', 'Norsk nynorsk'),
      new AppLanguage('pl', 'Polski'),
      new AppLanguage('pt', 'Português'),
      new AppLanguage('ro', 'Română'),
      new AppLanguage('sa', 'संस्कृतम्'),
      new AppLanguage('sah', 'Саха тыла'),
      new AppLanguage('sc', 'Sardu'),
      new AppLanguage('sdh', 'کوردی خوارگ'),
      new AppLanguage('sk', 'Slovenčina'),
      new AppLanguage('sq', 'Shqip'),
      new AppLanguage('sr', 'Српски'),
      new AppLanguage('sv', 'Svenska'),
      new AppLanguage('ta', 'தமிழ்'),
      new AppLanguage('te', 'తెలుగు'),
      new AppLanguage('th', 'ไทย'),
      new AppLanguage('tr', 'Türkçe'),
      new AppLanguage('tt', 'Татар'),
      new AppLanguage('uk', 'Українська'),
      new AppLanguage('uz', 'Oʻzbekcha'),
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
