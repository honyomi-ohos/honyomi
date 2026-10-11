// 主题：色板资源化（base/dark color.json）+ AppStorage 'palette' 状态绑定
// 组件用法：@StorageProp('palette') pal: ThemePalette = new ThemePalette()
//           .fontColor(this.pal.text)
// palette 由 Settings.applyTheme / applyAccent / pushPalette 重建并写入 AppStorage，
// 深浅色值引用 color.json 资源（随应用颜色模式自动解析），AMOLED/accent 由构建时选取。

export class ThemePalette {
  bg: ResourceColor = '#F2F3F7';
  card: ResourceColor = '#FFFFFF';
  chip: ResourceColor = '#E9ECF2';
  divider: ResourceColor = '#E5E7EB';
  text: ResourceColor = '#16181D';
  sub: ResourceColor = '#6B7280';
  primary: ResourceColor = '#4E6E9E';
  primarySoft: ResourceColor = '#E0E7F0';
  badgeRed: ResourceColor = '#E5484D';
  badgeBlue: ResourceColor = '#3D7DC8';
}

export class Theme {
  static accentNames(): string[] {
    return ['blue', 'green', 'pink', 'purple', 'orange'];
  }

  static accentLabel(name: string): Resource {
    if (name === 'green') {
      return $r('app.string.theme_accent_green');
    }
    if (name === 'pink') {
      return $r('app.string.theme_accent_pink');
    }
    if (name === 'purple') {
      return $r('app.string.theme_accent_purple');
    }
    if (name === 'orange') {
      return $r('app.string.theme_accent_orange');
    }
    return $r('app.string.theme_accent_blue');
  }

  static accentDot(name: string): string {
    if (name === 'green') {
      return '#388E64';
    }
    if (name === 'pink') {
      return '#D45E88';
    }
    if (name === 'purple') {
      return '#7B5EA7';
    }
    if (name === 'orange') {
      return '#E07840';
    }
    return '#4E6E9E';
  }

  // 构建 palette：AMOLED 仅深色模式生效；accent 决定 primary/primarySoft
  static buildPalette(dark: boolean, amoled: boolean, accent: string): ThemePalette {
    const pal: ThemePalette = new ThemePalette();
    pal.bg = $r('app.color.honyomi_bg');
    pal.card = $r('app.color.honyomi_card');
    pal.chip = $r('app.color.honyomi_chip');
    pal.divider = $r('app.color.honyomi_divider');
    pal.text = $r('app.color.honyomi_text');
    pal.sub = $r('app.color.honyomi_sub');
    pal.badgeRed = $r('app.color.honyomi_badge_red');
    pal.badgeBlue = $r('app.color.honyomi_badge_blue');
    if (dark && amoled) {
      pal.bg = $r('app.color.honyomi_bg_amoled');
      pal.card = $r('app.color.honyomi_card_amoled');
      pal.chip = $r('app.color.honyomi_chip_amoled');
      pal.divider = $r('app.color.honyomi_divider_amoled');
    }
    if (accent === 'green') {
      pal.primary = $r('app.color.honyomi_primary_green');
      pal.primarySoft = $r('app.color.honyomi_primary_soft_green');
    } else if (accent === 'pink') {
      pal.primary = $r('app.color.honyomi_primary_pink');
      pal.primarySoft = $r('app.color.honyomi_primary_soft_pink');
    } else if (accent === 'purple') {
      pal.primary = $r('app.color.honyomi_primary_purple');
      pal.primarySoft = $r('app.color.honyomi_primary_soft_purple');
    } else if (accent === 'orange') {
      pal.primary = $r('app.color.honyomi_primary_orange');
      pal.primarySoft = $r('app.color.honyomi_primary_soft_orange');
    } else {
      pal.primary = $r('app.color.honyomi_primary_blue');
      pal.primarySoft = $r('app.color.honyomi_primary_soft_blue');
    }
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
