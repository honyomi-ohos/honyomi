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
  bg: string = '#F2F3F7';
  card: string = '#FFFFFF';
  chip: string = '#E9ECF2';
  divider: string = '#E5E7EB';
  text: string = '#16181D';
  sub: string = '#6B7280';
  primary: string = '#4E6E9E';
  onPrimary: string = '#FFFFFF';
  primarySoft: string = '#E0E7F0';
  onPrimarySoft: string = '#4E6E9E';
  badgeRed: string = '#E5484D';
  badgeBlue: string = '#3D7DC8';
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
      const defLight = new ThemeScheme('#F2F3F7', '#FFFFFF', '#E9ECF2', '#E5E7EB',
        '#16181D', '#6B7280', '#4E6E9E', '#FFFFFF', '#E0E7F0', '#4E6E9E', '#E5484D', '#3D7DC8');
      const defDark = new ThemeScheme('#101318', '#1B212B', '#242B37', '#2A313D',
        '#ECEEF2', '#8B93A1', '#7B9BD4', '#FFFFFF', '#28303C', '#7B9BD4', '#E5484D', '#3D7DC8');
      const defAmoled = new ThemeScheme('#000000', '#0D0D0D', '#161616', '#1E1E1E',
        '#ECEEF2', '#8B93A1', '#7B9BD4', '#FFFFFF', '#28303C', '#7B9BD4', '#E5484D', '#3D7DC8');
      // ---- tachiyomi（M3 蓝色）----
      const tachiDark = new ThemeScheme('#1B1B1F', '#1E1C22', '#211F26', '#44464F',
        '#E3E2E6', '#C5C6D0', '#B0C6FF', '#002D6E', '#00429B', '#D9E2FF', '#FFB4AB', '#B0C6FF');
      const tachiLight = new ThemeScheme('#FEFBFF', '#F7F2FA', '#F3EDF7', '#C5C6D0',
        '#1B1B1F', '#44464F', '#0058CA', '#FFFFFF', '#D9E2FF', '#001945', '#BA1A1A', '#0058CA');
      // ---- midnight_dusk ----
      const duskDark = new ThemeScheme('#16151D', '#251522', '#281624', '#49454F',
        '#E5E1E5', '#D6C1C4', '#F02475', '#FFFFFF', '#BD1C5C', '#FFFFFF', '#FFB4AB', '#F02475');
      const duskLight = new ThemeScheme('#FFFBFF', '#E8D1DD', '#F9E6F1', '#CAC4D0',
        '#1C1B1F', '#524346', '#BB0054', '#FFFFFF', '#FFD9E1', '#3F0017', '#BA1A1A', '#BB0054');
      // ---- nord ----
      const nordDark = new ThemeScheme('#2E3440', '#3E4756', '#414C5C', '#90939A',
        '#ECEFF4', '#ECEFF4', '#88C0D0', '#2E3440', '#88C0D0', '#2E3440', '#FFB4AB', '#81A1C1');
      const nordLight = new ThemeScheme('#ECEFF4', '#D6DCE6', '#DAE0EA', '#D8DEE9',
        '#2E3440', '#2E3440', '#5E81AC', '#000000', '#5E81AC', '#000000', '#BA1A1A', '#81A1C1');
      // ---- strawberry_daiquiri ----
      const strawDark = new ThemeScheme('#201A1A', '#302525', '#322727', '#594042',
        '#F7DCDD', '#E1BEC0', '#FFB2B8', '#67001D', '#D53855', '#FFFFFF', '#FFB4AB', '#ED4A65');
      const strawLight = new ThemeScheme('#FAFAFA', '#FDE2E3', '#F6EAED', '#E1BEC0',
        '#261819', '#594042', '#A10833', '#FFFFFF', '#D53855', '#FFFFFF', '#BA1A1A', '#A10833');
      // ---- tako ----
      const takoDark = new ThemeScheme('#21212E', '#262636', '#2A2A3C', '#49454F',
        '#E3E0F2', '#CBC4CE', '#F3B375', '#38294E', '#F3B375', '#38294E', '#FFB4AB', '#F3B375');
      const takoLight = new ThemeScheme('#F7F5FF', '#DFD8E2', '#E8E0EB', '#CAC4D0',
        '#1B1B22', '#49454E', '#66577E', '#F3B375', '#66577E', '#F3B375', '#BA1A1A', '#66577E');
      // ---- teal_turquoise ----
      const tealDark = new ThemeScheme('#202125', '#222F31', '#233133', '#49454F',
        '#DFDEDA', '#DFDEDA', '#40E0D0', '#000000', '#40E0D0', '#000000', '#FFB4AB', '#40E0D0');
      const tealLight = new ThemeScheme('#FAFAFA', '#E6EEEC', '#EBF3F1', '#CAC4D0',
        '#050505', '#050505', '#008080', '#FFFFFF', '#008080', '#FFFFFF', '#BA1A1A', '#008080');
      // ---- tidal_wave ----
      const tidalDark = new ThemeScheme('#001C3B', '#072947', '#082B4B', '#49454F',
        '#D5E3FF', '#BFC8CC', '#5ED4FC', '#003544', '#004D61', '#B8EAFF', '#FFB4AB', '#5ED4FC');
      const tidalLight = new ThemeScheme('#FDFBFF', '#E5ECF1', '#E8EFF5', '#CAC4D0',
        '#001C3B', '#40484C', '#006780', '#FFFFFF', '#B4D4DF', '#001F28', '#BA1A1A', '#006780');
      // ---- yin_yang ----
      const yinDark = new ThemeScheme('#1E1E1E', '#2D2D2D', '#313131', '#49454F',
        '#E6E6E6', '#D1D1D1', '#FFFFFF', '#5A5A5A', '#FFFFFF', '#000000', '#FFB4AB', '#FFFFFF');
      const yinLight = new ThemeScheme('#FDFDFD', '#DADADA', '#E8E8E8', '#CAC4D0',
        '#222222', '#515151', '#000000', '#FFFFFF', '#000000', '#FFFFFF', '#BA1A1A', '#000000');
      // ---- yotsuba ----
      const yotsDark = new ThemeScheme('#211A18', '#312521', '#332723', '#49454F',
        '#EDE0DD', '#D8C2BC', '#FFB59D', '#5F1600', '#862200', '#FFDBCF', '#FFB4AB', '#FFB59D');
      const yotsLight = new ThemeScheme('#FCFCFC', '#F1E7E4', '#F6EBE7', '#CAC4D0',
        '#211A18', '#53433F', '#AE3200', '#FFFFFF', '#FFDBCF', '#3B0A00', '#BA1A1A', '#AE3200');
      // ---- tokyo_night ----
      const tokyoDark = new ThemeScheme('#222436', '#292C44', '#2D304B', '#444A73',
        '#C8D3F5', '#828BB8', '#82AAFF', '#1B1D2B', '#444A73', '#9AB8FF', '#FF757F', '#86E1FC');
      const tokyoLight = new ThemeScheme('#E1E2E7', '#D0D5E3', '#C1C9DF', '#A8AECB',
        '#3760BF', '#6172B0', '#2E7DE9', '#FFFFFF', '#92A6D5', '#15386A', '#F52A65', '#007197');
      // ---- monochrome（深色即纯黑，AMOLED 与深色一致）----
      const monoDark = new ThemeScheme('#000000', '#000000', '#000000', '#FFFFFF',
        '#FFFFFF', '#FFFFFF', '#FFFFFF', '#000000', '#FFFFFF', '#000000', '#FFFFFF', '#FFFFFF');
      const monoLight = new ThemeScheme('#FFFFFF', '#FFFFFF', '#FFFFFF', '#000000',
        '#000000', '#000000', '#000000', '#FFFFFF', '#000000', '#FFFFFF', '#000000', '#000000');
      // ---- green_apple ----
      const appleDark = new ThemeScheme('#0F1510', '#181D18', '#1C211C', '#3F493F',
        '#DFE4DB', '#BECABC', '#7ADB8F', '#003917', '#017737', '#FFFFFF', '#FFB4AB', '#7ADB8F');
      const appleLight = new ThemeScheme('#F6FBF2', '#F0F5EC', '#EAEFE6', '#BECABC',
        '#181D18', '#3F493F', '#005927', '#FFFFFF', '#188140', '#FFFFFF', '#BA1A1A', '#005927');
      // ---- lavender ----
      const lavDark = new ThemeScheme('#111129', '#171531', '#1D193B', '#4A4453',
        '#E7E0EC', '#CBC3D6', '#A177FF', '#3D0090', '#A177FF', '#FFFFFF', '#FFB4AB', '#A177FF');
      const lavLight = new ThemeScheme('#EDE2FF', '#DED0F1', '#E4D5F8', '#CBC3D6',
        '#1D1A22', '#4A4453', '#6D41C8', '#FFFFFF', '#7B46AF', '#130038', '#BA1A1A', '#7B46AF');
      // ---- catppuccin ----
      const catDark = new ThemeScheme('#181825', '#1E1E2E', '#1E1E2E', '#585B70',
        '#CDD6F4', '#CDD6F4', '#CBA6F7', '#11111B', '#CBA6F7', '#11111B', '#F38BA8', '#B4BEFE');
      const catLight = new ThemeScheme('#E6E9EF', '#EFF1F5', '#EFF1F5', '#ACB0BE',
        '#4C4F69', '#4C4F69', '#8839EF', '#DCE0E8', '#8839EF', '#DCE0E8', '#D20F39', '#7287FD');
      // ---- kanagawa（浮世绘：和纸 / 墨底 + 浪青）----
      const kanaDark = new ThemeScheme('#1F1F28', '#2A2A37', '#363646', '#54546D',
        '#DCD7BA', '#C4C0A8', '#A8C4F5', '#1A1B26', '#2A4060', '#D6E6FF', '#FF7B81', '#8FCBE0');
      const kanaLight = new ThemeScheme('#F2ECBC', '#E7DFB0', '#DCD5AC', '#B5B094',
        '#3D3D52', '#5A574A', '#2F4F86', '#F7F3E4', '#C5D6EC', '#1E3A68', '#B4233A', '#2F6F86');
      // ---- rose_pine（玫瑰松：暖纸底 + 鸢尾紫）----
      const roseDark = new ThemeScheme('#191724', '#2A2638', '#322C42', '#524E68',
        '#E0DEF4', '#B4AFC8', '#D4B8F5', '#1E1630', '#3A3054', '#F0E4FF', '#FF8FA8', '#8FD4DE');
      const roseLight = new ThemeScheme('#F6EBE1', '#FFF9F4', '#F3E6DB', '#E4D3C6',
        '#3E3654', '#6A6478', '#6B4C8A', '#FFF9F4', '#E6D4F4', '#4A2E68', '#A33B55', '#1F6A78');
      // ---- gruvbox（暖褐：复古纸色 + 琥珀橙）----
      const gruvDark = new ThemeScheme('#282828', '#32302F', '#3C3836', '#665C54',
        '#EBDBB2', '#C4B596', '#FEA040', '#2A1A08', '#5A3A18', '#FFE0B8', '#FF7A6A', '#8EC4C4');
      const gruvLight = new ThemeScheme('#FBF1C7', '#F2E5BC', '#EBDBB2', '#D5C4A1',
        '#3C3836', '#665C54', '#9A3E00', '#FFF8E8', '#F0C890', '#6A2800', '#9D1C16', '#076678');
      // ---- dracula（德古拉：夜紫）----
      const dracDark = new ThemeScheme('#282A36', '#313244', '#3A3C52', '#6272A4',
        '#F8F8F2', '#C8CAD6', '#D0B0FF', '#24183A', '#4A3A72', '#F3E8FF', '#FF6E6E', '#8BE9FD');
      const dracLight = new ThemeScheme('#EFEDF6', '#FFFFFF', '#E6E3F2', '#D2CEE2',
        '#282A36', '#5C6080', '#5A3EAE', '#FFFFFF', '#E0D4FA', '#3A2278', '#C42B45', '#0B6E86');
      // ---- matcha（抹茶：偏黄的茶绿）----
      const matchaDark = new ThemeScheme('#141A12', '#222C1C', '#2A3622', '#4A5A40',
        '#E4EDD8', '#B4C4A4', '#C6DE78', '#1A2408', '#314218', '#E8F4B8', '#FF8A7A', '#8FCBB8');
      const matchaLight = new ThemeScheme('#E8EEDC', '#FFFFFF', '#DCE6CC', '#C6D4B4',
        '#1C2414', '#55634A', '#3E6B22', '#F4F8EC', '#D0E4B4', '#2A4C16', '#B33A32', '#1F6A58');
      // ---- sakura（樱：淡粉）----
      const sakuraDark = new ThemeScheme('#120C10', '#261820', '#321E28', '#5C4050',
        '#F8E8EE', '#D4B4C0', '#F5B0CC', '#3A1020', '#5A2840', '#FFE0EC', '#FF8A96', '#D4B0E8');
      const sakuraLight = new ThemeScheme('#FFF1F4', '#F6DCE4', '#EEC8D4', '#E2B8C6',
        '#2C161C', '#6E4C5A', '#A32050', '#FFFFFF', '#F0B8CE', '#7A1438', '#C42B3E', '#6A3E96');
      // ---- kintsugi（金缮：陶黑 / 素瓷 + 金）----
      const kintDark = new ThemeScheme('#141210', '#26221C', '#302A22', '#564C40',
        '#F4EEE4', '#C8BBA6', '#F0C36A', '#2A1C06', '#4A3814', '#FFE8B8', '#FF8A78', '#9EC0D4');
      const kintLight = new ThemeScheme('#EFE8DC', '#FFFFFF', '#E7D8C0', '#D8C8B0',
        '#1E1A14', '#645C4E', '#7A4E0C', '#FFF8EC', '#F0D6A4', '#5C3A08', '#B33A32', '#2E5E80');
      // ---- glacier（冰川：冷调冰青）----
      const glacDark = new ThemeScheme('#0E161C', '#1C2832', '#243440', '#3E5666',
        '#E6F2F6', '#B0C6D2', '#8EE0F4', '#042028', '#1A4454', '#D4F4FC', '#FF8A86', '#B4D0F0');
      const glacLight = new ThemeScheme('#E7F1F6', '#FFFFFF', '#D5E6EF', '#C0D4E0',
        '#102028', '#4E6674', '#0C6480', '#F4FBFD', '#C8E6F0', '#084456', '#B33A3A', '#2A5688');
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
          monoLight, monoDark, monoDark),
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
