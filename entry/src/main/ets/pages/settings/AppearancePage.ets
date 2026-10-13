import { common } from '@kit.AbilityKit';
import { Theme, ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Languages } from '../../common/Languages';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, PrefSwitchRow, TextRow } from '../components/Prefs';

// 外观设置：语言 / 主题模式 / 主题色 / AMOLED
@Component
export struct AppearancePage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('accent') accent: string = 'blue';
  @StorageProp('appLanguage') appLanguage: string = 'auto';
  @State themeMode: string = 'auto';

  aboutToAppear(): void {
    this.themeMode = Settings.getThemeMode();
  }

  private applyTheme(mode: string): void {
    this.themeMode = mode;
    Settings.setThemeMode(mode);
    const systemDark = AppStorage.get<boolean>('isDarkSystem') ?? false;
    Settings.applyTheme(systemDark);
    Settings.applyColorMode(Util.hostAbilityContext(this.getUIContext()));
  }

  @Builder
  modeChip(label: Resource | string, mode: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.themeMode === mode ? '#FFFFFF' : this.pal.text)
      .backgroundColor(this.themeMode === mode ? this.pal.primary : this.pal.chip)
      .borderRadius(16)
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .onClick(() => {
        this.applyTheme(mode);
      })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.appearance_title') })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: $r('app.string.appearance_language') }) {
              TextRow({
                title: $r('app.string.appearance_language'),
                value: this.appLanguage === 'auto'
                  ? $r('app.string.lang_follow_system')
                  : Languages.displayName(this.appLanguage),
                onTap: (): void => {
                  this.pathStack.pushPathByName('Language', null);
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

            PrefGroup({ groupTitle: $r('app.string.appearance_accent_color') }) {
              Row({ space: 18 }) {
                ForEach(Theme.accentNames(), (name: string) => {
                  Column({ space: 4 }) {
                    Column() {
                      if (this.accent === name) {
                        Column()
                          .width(12)
                          .height(12)
                          .borderRadius(6)
                          .backgroundColor('#FFFFFF')
                      }
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .backgroundColor(Theme.accentDot(name))
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .border({
                      width: this.accent === name ? 2 : 0,
                      color: this.pal.text
                    })
                    .onClick(() => {
                      this.accent = name;
                      Settings.setAccentColor(name);
                      Settings.applyAccent();
                    })
                    Text(Theme.accentLabel(name))
                      .fontSize(11)
                      .fontColor(this.pal.sub)
                  }
                  .alignItems(HorizontalAlign.Center)
                }, (name: string) => `accent-${name}`)
              }
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            }

            PrefGroup({ groupTitle: $r('app.string.appearance_other') }) {
              PrefSwitchRow({
                title: $r('app.string.appearance_amoled'),
                initValue: Settings.getAmoledMode(),
                apply: (value: boolean): void => {
                  Settings.setAmoledMode(value);
                  Settings.applyAccent();
                }
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
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
