import { common } from '@kit.AbilityKit';
import { Theme, ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SwitchRow } from '../components/Prefs';

// 外观设置：主题模式 / 主题色 / AMOLED
@Component
export struct AppearancePage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('accent') accent: string = 'blue';
  @State themeMode: string = 'auto';
  @State amoled: boolean = false;

  aboutToAppear(): void {
    this.themeMode = Settings.getThemeMode();
    this.amoled = Settings.getAmoledMode();
  }

  private applyTheme(mode: string): void {
    this.themeMode = mode;
    Settings.setThemeMode(mode);
    const systemDark = AppStorage.get<boolean>('isDarkSystem') ?? false;
    Settings.applyTheme(systemDark);
    Settings.applyColorMode(getContext(this) as common.UIAbilityContext);
  }

  @Builder
  modeChip(label: string, mode: string) {
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
        PageHeader({ title: '外观' })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: '主题模式' }) {
              Row({ space: 8 }) {
                this.modeChip('跟随系统', 'auto')
                this.modeChip('浅色', 'light')
                this.modeChip('深色', 'dark')
              }
              .padding({ left: 16, right: 16, top: 12, bottom: 14 })
            }

            PrefGroup({ groupTitle: '主题色' }) {
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

            PrefGroup({ groupTitle: '其他' }) {
              SwitchRow({
                title: 'AMOLED 纯黑背景',
                isOn: this.amoled,
                onChange: (value: boolean): void => {
                  this.amoled = value;
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
