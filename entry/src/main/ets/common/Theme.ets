// 主题系统（参考 Mihon AppTheme）：23 套内置主题，全部为程序化 hex 色板，
// 每套主题含 light / dark / amoled 三个变体；palette 由 Settings.applyTheme /
// applyAppTheme / pushPalette 重建并写入 AppStorage('palette')。
// 组件用法：@StorageProp('palette') pal: ThemePalette = new ThemePalette()
//           .fontColor(this.pal.text)
// 字段与 M3 的映射：bg=background card=surfaceContainerLow chip=surfaceContainer
// divider=outlineVariant text=onSurface sub=onSurfaceVariant primary=primary
// onPrimary=onPrimary primarySoft=primaryContainer onPrimarySoft=onPrimaryContainer
// badgeRed=error badgeBlue=secondary
export class ThemePalette {
  bg: string = '#F2F4F8';
  card: string = '#FFFFFF';
  chip: string = '#ECF0F4';
  divider: string = '#E5E8ED';
  text: string = '#16181D';
  sub: string = '#4C5A68';
  primary: string = '#345080';
  onPrimary: string = '#FFFFFF';
  primarySoft: string = '#E0E7F0';
  onPrimarySoft: string = '#203864';
  badgeRed: string = '#BE2E38';
  badgeBlue: string = '#2A5C9E';
}

// 主题单变体（浅色/深色/AMOLED 之一）的完整色值
export class ThemeScheme {
  bg: string;
  card: string;
  chip: string;
  divider: string;
  text: string;
  sub: string;
  primary: string;
  onPrimary: string;
  primarySoft: string;
  onPrimarySoft: string;
  badgeRed: string;
  badgeBlue: string;

  constructor(bg: string, card: string, chip: string, divider: string,
    text: string, sub: string, primary: string, onPrimary: string,
    primarySoft: string, onPrimarySoft: string, badgeRed: string, badgeBlue: string) {
    this.bg = bg;
    this.card = card;
    this.chip = chip;
    this.divider = divider;
    this.text = text;
    this.sub = sub;
    this.primary = primary;
    this.onPrimary = onPrimary;
    this.primarySoft = primarySoft;
    this.onPrimarySoft = onPrimarySoft;
    this.badgeRed = badgeRed;
    this.badgeBlue = badgeBlue;
  }
}

// 主题定义：id（持久化键值）+ 标签资源 + 三个色板变体
export class AppThemeDef {
  readonly id: string;
  readonly labelRes: Resource;
  readonly light: ThemeScheme;
  readonly dark: ThemeScheme;
  readonly amoled: ThemeScheme;

  constructor(id: string, labelRes: Resource, light: ThemeScheme,
    dark: ThemeScheme, amoled: ThemeScheme) {
    this.id = id;
    this.labelRes = labelRes;
    this.light = light;
    this.dark = dark;
    this.amoled = amoled;
  }
}

// AMOLED 变体：由深色变体派生（对齐 Mihon BaseColorScheme 纯黑覆盖），
// bg 纯黑、card/chip 取 #0C0C0C（M3 surfaceContainer 覆盖值），divider 保持深色值
function amoledVariant(dark: ThemeScheme): ThemeScheme {
  return new ThemeScheme('#000000', '#0C0C0C', '#0C0C0C', dark.divider, dark.text, dark.sub,
    dark.primary, dark.onPrimary, dark.primarySoft, dark.onPrimarySoft,
    dark.badgeRed, dark.badgeBlue);
}

export class Theme {
  private static themeList: AppThemeDef[] | undefined = undefined;

  // 主题目录（顺序即选择器展示顺序；首个为默认主题）
  static themes(): AppThemeDef[] {
    if (Theme.themeList === undefined) {
      // ---- default（Honyomi 原有外观，色值与 color.json 基准一致）----
      const defLight = new ThemeScheme('#F2F4F8', '#FFFFFF', '#ECF0F4', '#E5E8ED',
        '#16181D', '#4C5A68', '#345080', '#FFFFFF', '#E0E7F0', '#203864', '#BE2E38', '#2A5C9E');
      const defDark = new ThemeScheme('#101318', '#1B212B', '#242B37', '#3A4556',
        '#ECEEF2', '#9AA3B2', '#8EAEDE', '#162033', '#2C3C54', '#D0DEF4', '#FF8B90', '#7EAEF0');
      const defAmoled = new ThemeScheme('#000000', '#121212', '#1C1C1C', '#333333',
        '#ECEEF2', '#9AA3B2', '#8EAEDE', '#162033', '#2C3C54', '#D0DEF4', '#FF8B90', '#7EAEF0');
      // ---- tachiyomi（M3 蓝色）----
      const tachiDark = new ThemeScheme('#14141A', '#23232C', '#2E2E3A', '#555568',
        '#E6E4EA', '#C4C6D2', '#B4C8FF', '#06285E', '#1E3A78', '#E2EAFF', '#FFB4AB', '#B4C8FF');
      const tachiLight = new ThemeScheme('#F5F3F9', '#FFFFFF', '#F1EEF7', '#EBE7F2',
        '#1B1B1F', '#454654', '#0058CA', '#FFFFFF', '#EDF2FF', '#002A70', '#BA1A1A', '#0058CA');
      // ---- midnight_dusk ----
      const duskDark = new ThemeScheme('#140E14', '#2C1824', '#3C2230', '#6A4558',
        '#F6E8EE', '#C8A8B6', '#FF7AAB', '#3D001C', '#6E2044', '#FFD4E4', '#FFB4AB', '#FF7AAB');
      const duskLight = new ThemeScheme('#F9F3F6', '#FFFFFF', '#F8ECF1', '#F3E4EC',
        '#241820', '#5C4250', '#A00048', '#FFFFFF', '#FFEEF3', '#5C0028', '#BA1A1A', '#A00048');
      // ---- nord ----
      const nordDark = new ThemeScheme('#2E3440', '#3B4252', '#434C5E', '#616E88',
        '#ECEFF4', '#D8DEE9', '#9AD4E2', '#1E2834', '#3E6A78', '#E4F6F8', '#F2B4B8', '#A3C0DC');
      const nordLight = new ThemeScheme('#F3F4F8', '#FFFFFF', '#ECF0F4', '#E5E9EE',
        '#2E3440', '#4C566A', '#3A587E', '#FFFFFF', '#EFF2F7', '#2E3440', '#9A3E46', '#3A587E');
      // ---- strawberry_daiquiri ----
      const strawDark = new ThemeScheme('#1C1414', '#302222', '#402E2E', '#6E5254',
        '#F8E0E0', '#D4B0B4', '#FFC0C4', '#5C1824', '#6E2834', '#FFDCE0', '#FFB4AB', '#FF8A98');
      const strawLight = new ThemeScheme('#FBF3F3', '#FFFFFF', '#FAEBEC', '#F5E4E7',
        '#261819', '#68444A', '#920628', '#FFFFFF', '#FDEFF1', '#6A0422', '#B42330', '#920628');
      // ---- tako ----
      const takoDark = new ThemeScheme('#1A1A26', '#282836', '#343448', '#564E6A',
        '#E8E4F4', '#B8B0C6', '#F6C08A', '#3A2410', '#5A4030', '#FFE6CC', '#FFB4AB', '#F6C08A');
      const takoLight = new ThemeScheme('#F6F3FA', '#FFFFFF', '#F2EDF8', '#ECE6F2',
        '#1B1B22', '#524860', '#463268', '#FFE4C6', '#F5F0FA', '#3A2858', '#BA1A1A', '#463268');
      // ---- teal_turquoise ----
      const tealDark = new ThemeScheme('#12181A', '#1C2C2E', '#264044', '#4A6864',
        '#E4F2F0', '#B4C8C4', '#62E8D8', '#042422', '#0E4E4A', '#C8FFF4', '#FFB4AB', '#62E8D8');
      const tealLight = new ThemeScheme('#EEF5F4', '#FFFFFF', '#E7F1EF', '#DFEBE9',
        '#10201E', '#3A524E', '#006864', '#FFFFFF', '#E8F4F3', '#044444', '#BA1A1A', '#006864');
      // ---- tidal_wave ----
      const tidalDark = new ThemeScheme('#001428', '#0A3058', '#12406C', '#3A6484',
        '#D8E6FF', '#B4C8D6', '#6AD8FC', '#003544', '#085878', '#C8F2FF', '#FFB4AB', '#6AD8FC');
      const tidalLight = new ThemeScheme('#EFF5FA', '#FFFFFF', '#E7F0F7', '#E0EBF1',
        '#001C3B', '#384852', '#005870', '#FFFFFF', '#E9F4F9', '#003444', '#BA1A1A', '#005870');
      // ---- yin_yang ----
      const yinDark = new ThemeScheme('#121212', '#1E1E1E', '#2A2A2A', '#4A4A4A',
        '#F2F2F2', '#C4C4C4', '#FFFFFF', '#1A1A1A', '#E8E8E8', '#1A1A1A', '#FFB4AB', '#FFFFFF');
      const yinLight = new ThemeScheme('#F4F4F4', '#FFFFFF', '#EEEEEE', '#E8E8E8',
        '#1A1A1A', '#555555', '#111111', '#FFFFFF', '#F2F2F2', '#1A1A1A', '#B4232A', '#111111');
      // ---- yotsuba ----
      const yotsDark = new ThemeScheme('#1A1412', '#2E221C', '#3C2C26', '#6A544A',
        '#F4E8E2', '#D0B8AE', '#FFC0AA', '#5A1600', '#7A3018', '#FFE0D4', '#FFB4AB', '#FFC0AA');
      const yotsLight = new ThemeScheme('#F8F3F1', '#FFFFFF', '#F6EDEA', '#F1E6E3',
        '#211A18', '#58443E', '#962C00', '#FFFFFF', '#FFEFE8', '#581400', '#BA1A1A', '#962C00');
      // ---- tokyo_night ----
      const tokyoDark = new ThemeScheme('#1E2030', '#292C44', '#343858', '#4A5080',
        '#C8D3F5', '#A8B0D8', '#96BAFF', '#1A1E30', '#3A4478', '#D8E6FF', '#FF8A92', '#8EE4FC');
      const tokyoLight = new ThemeScheme('#F2F4F8', '#FFFFFF', '#ECEFF8', '#E5E9F2',
        '#1A3F86', '#4A5E90', '#1560C8', '#FFFFFF', '#ECF2FD', '#0E3878', '#C01040', '#0C6A88');
      // ---- monochrome（深色保留灰阶层次，AMOLED 再压成纯黑）----
      const monoDark = new ThemeScheme('#000000', '#161616', '#242424', '#3A3A3A',
        '#FFFFFF', '#B5B5B5', '#FFFFFF', '#000000', '#2E2E2E', '#FFFFFF', '#FFFFFF', '#FFFFFF');
      const monoLight = new ThemeScheme('#F4F4F4', '#FFFFFF', '#EEEEEE', '#E8E8E8',
        '#111111', '#555555', '#111111', '#FFFFFF', '#F1F1F1', '#111111', '#111111', '#111111');
      // ---- green_apple ----
      const appleDark = new ThemeScheme('#0E1510', '#1A2820', '#24362A', '#3E5646',
        '#E4F0E6', '#B4C8B6', '#7EDC92', '#063018', '#145C30', '#D8F8E0', '#FFB4AB', '#7EDC92');
      const appleLight = new ThemeScheme('#EFF6ED', '#FFFFFF', '#E8F1E6', '#E0EBDE',
        '#142016', '#3C5244', '#0C642E', '#FFFFFF', '#E9F5EC', '#084020', '#BA1A1A', '#0C642E');
      // ---- lavender ----
      const lavDark = new ThemeScheme('#100E22', '#1E1A36', '#2A2448', '#4E4670',
        '#EDE6F6', '#C4B8D4', '#C9B0FF', '#2A0858', '#3A2878', '#E8DCFF', '#FFB4AB', '#C9B0FF');
      const lavLight = new ThemeScheme('#F7F2FC', '#FFFFFF', '#F2EDFA', '#EDE6F5',
        '#1D1A22', '#524860', '#552EA6', '#FFFFFF', '#F5F0FD', '#3A1880', '#BA1A1A', '#552EA6');
      // ---- catppuccin ----
      const catDark = new ThemeScheme('#11111B', '#1E1E2E', '#313244', '#585B70',
        '#CDD6F4', '#A6ADC8', '#CBA6F7', '#11111B', '#3C3458', '#E8D8FF', '#F38BA8', '#89B4FA');
      const catLight = new ThemeScheme('#E3E6ED', '#EFF1F5', '#DEE2E9', '#D9DCE4',
        '#3C3F56', '#484C62', '#641EBC', '#FFFFFF', '#E8E1F6', '#401878', '#B8162C', '#3A4EBE');
      // ---- kanagawa（浮世绘：和纸 / 墨底 + 浪青）----
      const kanaDark = new ThemeScheme('#1F1F28', '#2A2A37', '#363646', '#54546D',
        '#DCD7BA', '#C4C0A8', '#A8C4F5', '#1A1B26', '#2A4060', '#D6E6FF', '#FF7B81', '#8FCBE0');
      const kanaLight = new ThemeScheme('#F2ECBC', '#E7DFB0', '#DCD5AC', '#B5B094',
        '#3D3D52', '#5A574A', '#2F4F86', '#F7F3E4', '#C5D6EC', '#1E3A68', '#B4233A', '#2F6F86');
      // ---- rose_pine（玫瑰松：暖纸底 + 鸢尾紫）----
      const roseDark = new ThemeScheme('#191724', '#2A2638', '#322C42', '#524E68',
        '#E0DEF4', '#B4AFC8', '#D4B8F5', '#1E1630', '#3A3054', '#F0E4FF', '#FF8FA8', '#8FD4DE');
      const roseLight = new ThemeScheme('#F8EDE4', '#FFF9F4', '#F5E9DE', '#EEE2D8',
        '#3E3654', '#6A6478', '#6B4C8A', '#FFF9F4', '#F5EAF4', '#4A2E68', '#A33B55', '#1F6A78');
      // ---- gruvbox（暖褐：复古纸色 + 琥珀橙）----
      const gruvDark = new ThemeScheme('#282828', '#32302F', '#3C3836', '#665C54',
        '#EBDBB2', '#C4B596', '#FEA040', '#2A1A08', '#5A3A18', '#FFE0B8', '#FF7A6A', '#8EC4C4');
      const gruvLight = new ThemeScheme('#FBF1C7', '#F2E5BC', '#EBDBB2', '#D5C4A1',
        '#3C3836', '#665C54', '#9A3E00', '#FFF8E8', '#F0C890', '#6A2800', '#9D1C16', '#076678');
      // ---- dracula（德古拉：夜紫）----
      const dracDark = new ThemeScheme('#282A36', '#313244', '#3A3C52', '#6272A4',
        '#F8F8F2', '#C8CAD6', '#D0B0FF', '#24183A', '#4A3A72', '#F3E8FF', '#FF6E6E', '#8BE9FD');
      const dracLight = new ThemeScheme('#F5F3F9', '#FFFFFF', '#F0EEF7', '#E9E8F1',
        '#282A36', '#5C6080', '#5A3EAE', '#FFFFFF', '#F5F0FD', '#3A2278', '#C42B45', '#0B6E86');
      // ---- matcha（抹茶：偏黄的茶绿）----
      const matchaDark = new ThemeScheme('#141A12', '#222C1C', '#2A3622', '#4A5A40',
        '#E4EDD8', '#B4C4A4', '#C6DE78', '#1A2408', '#314218', '#E8F4B8', '#FF8A7A', '#8FCBB8');
      const matchaLight = new ThemeScheme('#F2F6EB', '#FFFFFF', '#ECF1E3', '#E4EBDC',
        '#1C2414', '#55634A', '#3E6B22', '#F4F8EC', '#EDF4E2', '#2A4C16', '#B33A32', '#1F6A58');
      // ---- sakura（樱：淡粉）----
      const sakuraDark = new ThemeScheme('#120C10', '#261820', '#321E28', '#5C4050',
        '#F8E8EE', '#D4B4C0', '#F5B0CC', '#3A1020', '#5A2840', '#FFE0EC', '#FF8A96', '#D4B0E8');
      const sakuraLight = new ThemeScheme('#FFF1F4', '#FFFFFF', '#F9ECF0', '#F4E4EA',
        '#2C161C', '#6E4C5A', '#A32050', '#FFFFFF', '#FCEEF4', '#7A1438', '#C42B3E', '#6A3E96');
      // ---- kintsugi（金缮：陶黑 / 素瓷 + 金）----
      const kintDark = new ThemeScheme('#141210', '#26221C', '#302A22', '#564C40',
        '#F4EEE4', '#C8BBA6', '#F0C36A', '#2A1C06', '#4A3814', '#FFE8B8', '#FF8A78', '#9EC0D4');
      const kintLight = new ThemeScheme('#F7F3ED', '#FFFFFF', '#F5EEE4', '#EEE7DD',
        '#1E1A14', '#645C4E', '#7A4E0C', '#FFF8EC', '#FAF2E1', '#5C3A08', '#B33A32', '#2E5E80');
      // ---- glacier（冰川：冷调冰青）----
      const glacDark = new ThemeScheme('#0E161C', '#1C2832', '#243440', '#3E5666',
        '#E6F2F6', '#B0C6D2', '#8EE0F4', '#042028', '#1A4454', '#D4F4FC', '#FF8A86', '#B4D0F0');
      const glacLight = new ThemeScheme('#EEF5F9', '#FFFFFF', '#E7F1F6', '#E0EAF0',
        '#102028', '#4E6674', '#0C6480', '#F4FBFD', '#E8F4F9', '#084456', '#B33A3A', '#2A5688');
      Theme.themeList = [
        new AppThemeDef('default', $r('app.string.theme_name_default'), defLight, defDark, defAmoled),
        new AppThemeDef('tachiyomi', $r('app.string.theme_name_tachiyomi'),
          tachiLight, tachiDark, amoledVariant(tachiDark)),
        new AppThemeDef('midnight_dusk', $r('app.string.theme_name_midnight_dusk'),
          duskLight, duskDark, amoledVariant(duskDark)),
        new AppThemeDef('nord', $r('app.string.theme_name_nord'),
          nordLight, nordDark, amoledVariant(nordDark)),
        new AppThemeDef('strawberry_daiquiri', $r('app.string.theme_name_strawberry_daiquiri'),
          strawLight, strawDark, amoledVariant(strawDark)),
        new AppThemeDef('tako', $r('app.string.theme_name_tako'),
          takoLight, takoDark, amoledVariant(takoDark)),
        new AppThemeDef('teal_turquoise', $r('app.string.theme_name_teal_turquoise'),
          tealLight, tealDark, amoledVariant(tealDark)),
        new AppThemeDef('tidal_wave', $r('app.string.theme_name_tidal_wave'),
          tidalLight, tidalDark, amoledVariant(tidalDark)),
        new AppThemeDef('yin_yang', $r('app.string.theme_name_yin_yang'),
          yinLight, yinDark, amoledVariant(yinDark)),
        new AppThemeDef('yotsuba', $r('app.string.theme_name_yotsuba'),
          yotsLight, yotsDark, amoledVariant(yotsDark)),
        new AppThemeDef('tokyo_night', $r('app.string.theme_name_tokyo_night'),
          tokyoLight, tokyoDark, amoledVariant(tokyoDark)),
        new AppThemeDef('monochrome', $r('app.string.theme_name_monochrome'),
          monoLight, monoDark, amoledVariant(monoDark)),
        new AppThemeDef('green_apple', $r('app.string.theme_name_green_apple'),
          appleLight, appleDark, amoledVariant(appleDark)),
        new AppThemeDef('lavender', $r('app.string.theme_name_lavender'),
          lavLight, lavDark, amoledVariant(lavDark)),
        new AppThemeDef('catppuccin', $r('app.string.theme_name_catppuccin'),
          catLight, catDark, amoledVariant(catDark)),
        new AppThemeDef('kanagawa', $r('app.string.theme_name_kanagawa'),
          kanaLight, kanaDark, amoledVariant(kanaDark)),
        new AppThemeDef('rose_pine', $r('app.string.theme_name_rose_pine'),
          roseLight, roseDark, amoledVariant(roseDark)),
        new AppThemeDef('gruvbox', $r('app.string.theme_name_gruvbox'),
          gruvLight, gruvDark, amoledVariant(gruvDark)),
        new AppThemeDef('dracula', $r('app.string.theme_name_dracula'),
          dracLight, dracDark, amoledVariant(dracDark)),
        new AppThemeDef('matcha', $r('app.string.theme_name_matcha'),
          matchaLight, matchaDark, amoledVariant(matchaDark)),
        new AppThemeDef('sakura', $r('app.string.theme_name_sakura'),
          sakuraLight, sakuraDark, amoledVariant(sakuraDark)),
        new AppThemeDef('kintsugi', $r('app.string.theme_name_kintsugi'),
          kintLight, kintDark, amoledVariant(kintDark)),
        new AppThemeDef('glacier', $r('app.string.theme_name_glacier'),
          glacLight, glacDark, amoledVariant(glacDark))
      ];
    }
    return Theme.themeList;
  }

  static isValidTheme(id: string): boolean {
    for (const t of Theme.themes()) {
      if (t.id === id) {
        return true;
      }
    }
    return false;
  }

  // 按 id 查找主题，未命中回退默认主题（目录首个）
  static findTheme(id: string): AppThemeDef {
    for (const t of Theme.themes()) {
      if (t.id === id) {
        return t;
      }
    }
    return Theme.themes()[0];
  }

  // 取主题在指定模式下的色板变体（AMOLED 仅深色模式生效）
  static colorsFor(themeId: string, dark: boolean, amoled: boolean): ThemeScheme {
    const theme: AppThemeDef = Theme.findTheme(themeId);
    if (!dark) {
      return theme.light;
    }
    return amoled ? theme.amoled : theme.dark;
  }

  // 构建 palette：由主题目录 + 深浅模式 + AMOLED 决定全部字段
  static buildPalette(themeId: string, dark: boolean, amoled: boolean): ThemePalette {
    const c: ThemeScheme = Theme.colorsFor(themeId, dark, amoled);
    const pal: ThemePalette = new ThemePalette();
    pal.bg = c.bg;
    pal.card = c.card;
    pal.chip = c.chip;
    pal.divider = c.divider;
    pal.text = c.text;
    pal.sub = c.sub;
    pal.primary = c.primary;
    pal.onPrimary = c.onPrimary;
    pal.primarySoft = c.primarySoft;
    pal.onPrimarySoft = c.onPrimarySoft;
    pal.badgeRed = c.badgeRed;
    pal.badgeBlue = c.badgeBlue;
    return pal;
  }

  // 阅读器背景：readerTheme 0=白 1=黑 2=灰 3=自动（跟随深色模式）
  static readerBg(theme: number, dark: boolean): string {
    if (theme === 0) {
      return '#FFFFFF';
    }
    if (theme === 1) {
      return '#000000';
    }
    if (theme === 2) {
      return '#3A3A3A';
    }
    return dark ? '#000000' : '#FFFFFF';
  }

  // 条漫加载占位/错误提示色（随深浅色）
  static readerPlaceholder(dark: boolean): string {
    return dark ? '#80FFFFFF' : '#80000000';
  }
}
