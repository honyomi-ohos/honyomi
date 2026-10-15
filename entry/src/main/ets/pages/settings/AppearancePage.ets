import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Languages } from '../../common/Languages';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, PrefSwitchRow, TextRow } from '../components/Prefs';
import { ThemePicker } from '../components/ThemePicker';

// 外观设置内容（可嵌入 lg 设置双栏右栏）：语言 / 主题模式 / 主题 / AMOLED
@Component
export struct AppearanceContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('appTheme') appTheme: string = 'default';
  @StorageProp('appLanguage') appLanguage: string = 'auto';
  @StorageProp('isDark') isDark: boolean = false;
  @State themeMode: string = 'auto';
  // 二级页跳转：手机壳内为 push 路由；lg 双栏内为右栏切换
  onNavigate: (route: string) => void = (route: string) => {};

  aboutToAppear(): void {
    this.themeMode = Settings.getThemeMode();
  }

  private applyMode(mode: string): void {
    this.themeMode = mode;
    Settings.setThemeMode(mode);
    const systemDark = AppStorage.get<boolean>('isDarkSystem') ?? false;
    Settings.applyTheme(systemDark);
    Settings.applyColorMode(Util.hostAbilityContext(this.getUIContext()));
  }

  private pickTheme(id: string): void {
    Settings.setAppThemeId(id);
    Settings.applyAppTheme(Util.hostAbilityContext(this.getUIContext()));
  }

  @Builder
  modeChip(label: Resource | string, mode: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.themeMode === mode ? this.pal.onPrimary : this.pal.text)
      .backgroundColor(this.themeMode === mode ? this.pal.primary : this.pal.chip)
      .borderRadius(16)
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .onClick(() => {
        this.applyMode(mode);
      })
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.appearance_language') }) {
          TextRow({
            title: $r('app.string.appearance_language'),
            value: this.appLanguage === 'auto'
              ? $r('app.string.lang_follow_system')
              : Languages.displayName(this.appLanguage),
            onTap: (): void => {
              this.onNavigate('Language');
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.appearance_theme_mode') }) {
          Row({ space: 8 }) {
            this.modeChip($r('app.string.appearance_theme_auto'), 'auto')
            this.modeChip($r('app.string.appearance_theme_light'), 'light')
            this.modeChip($r('app.string.appearance_theme_dark'), 'dark')
          }
          .padding({ left: 16, right: 16, top: 12, bottom: 14 })
        }

        PrefGroup({ groupTitle: $r('app.string.appearance_theme') }) {
          ThemePicker({
            selectedTheme: this.appTheme,
            onPick: (id: string): void => {
              this.pickTheme(id);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.appearance_other') }) {
          PrefSwitchRow({
            title: $r('app.string.appearance_amoled'),
            initValue: Settings.getAmoledMode(),
            switchEnabled: this.isDark,
            apply: (value: boolean): void => {
              Settings.setAmoledMode(value);
              Settings.applyAppTheme(Util.hostAbilityContext(this.getUIContext()));
            }
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }
}

// 外观设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct AppearancePage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Consume('navStack') pathStack: NavPathStack;

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.appearance_title') })
        AppearanceContent({
          onNavigate: (route: string): void => {
            this.pathStack.pushPathByName(route, null);
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function AppearanceBuilder() {
  AppearancePage()
}
