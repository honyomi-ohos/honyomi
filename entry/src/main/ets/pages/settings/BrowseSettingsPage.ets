import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SwitchRow } from '../components/Prefs';

// 浏览设置：NSFW 源显示
@Component
export struct BrowseSettingsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State showNsfw: boolean = false;

  aboutToAppear(): void {
    this.showNsfw = Settings.getShowNsfw();
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '浏览' })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: '内容' }) {
              SwitchRow({
                title: '显示成人内容源 (NSFW)',
                isOn: this.showNsfw,
                onChange: (value: boolean): void => {
                  this.showNsfw = value;
                  Settings.setShowNsfw(value);
                }
              })
            }
            Text('开启后，插件声明为成人内容的源会出现在浏览页中')
              .fontSize(12)
              .fontColor(this.pal.sub)
              .margin({ left: 20, top: 8 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
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
