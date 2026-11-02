// 阅读器主题映射（0=白 1=黑 2=灰 3=自动跟随深色模式 4=纸张护眼米黄）：
// 背景明暗同步 ReaderChrome 玻璃前景、正文/次级文字色推导，两阅读器共用
export class ReaderThemeState {
  // 解析主题生效值：自动主题按系统深浅色落到黑/白
  static resolveThemeValue(readerTheme: number, isDark: boolean): number {
    return readerTheme === 3 ? (isDark ? 1 : 0) : readerTheme;
  }

  // 阅读背景是否为深色（白/纸张为浅色）
  static isBgDark(readerTheme: number, isDark: boolean): boolean {
    const t: number = ReaderThemeState.resolveThemeValue(readerTheme, isDark);
    return t !== 0 && t !== 4;
  }

  // 背景明暗写入 AppStorage，供 ReaderChrome 玻璃前景取高对比色
  static syncReaderBgDark(readerTheme: number, isDark: boolean): void {
    AppStorage.setOrCreate('readerBgDark', ReaderThemeState.isBgDark(readerTheme, isDark));
  }

  // 正文/过渡文字色：白底/纸张底深色字，黑/灰底浅色字；
  // colorScheme 显式指定文字配色（'light' 浅字 / 'dark' 深字）时优先，'auto' 按背景推导
  static readerTextColor(readerTheme: number, isDark: boolean, colorScheme: string): string {
    if (colorScheme === 'light') {
      return '#ECEEF2';
    }
    if (colorScheme === 'dark') {
      return '#16181D';
    }
    const t: number = ReaderThemeState.resolveThemeValue(readerTheme, isDark);
    return t === 0 || t === 4 ? '#16181D' : '#ECEEF2';
  }

  // 次级文字色（带透明度）
  static readerSubColor(readerTheme: number, isDark: boolean): string {
    const t: number = ReaderThemeState.resolveThemeValue(readerTheme, isDark);
    return t === 0 || t === 4 ? '#9916181D' : '#99ECEEF2';
  }
}
