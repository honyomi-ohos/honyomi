// 主题色（浅色/深色双套，跟随 AppStorage 'isDark'）

export class Theme {
  static bg(dark: boolean): string {
    return dark ? '#101318' : '#F2F3F7';
  }

  static card(dark: boolean): string {
    return dark ? '#1B212B' : '#FFFFFF';
  }

  static text(dark: boolean): string {
    return dark ? '#ECEEF2' : '#16181D';
  }

  static sub(dark: boolean): string {
    return dark ? '#8B93A1' : '#6B7280';
  }

  static primary(dark: boolean): string {
    return dark ? '#7B9BD4' : '#4E6E9E';
  }

  static chip(dark: boolean): string {
    return dark ? '#242B37' : '#E9ECF2';
  }

  static divider(dark: boolean): string {
    return dark ? '#2A313D' : '#E5E7EB';
  }

  static readerBg(dark: boolean): string {
    return dark ? '#000000' : '#FFFFFF';
  }
}
