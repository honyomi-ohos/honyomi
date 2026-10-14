import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, PrefSwitchRow } from '../components/Prefs';

// 浏览设置内容：NSFW 源显示
@Component
export struct BrowseSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    Scroll() {
      Column() {
        PrefGroup({ groupTitle: $r('app.string.browse_set_content') }) {
          PrefSwitchRow({
            title: $r('app.string.browse_set_show_nsfw'),
            initValue: Settings.getShowNsfw(),
            apply: (value: boolean): void => {
              Settings.setShowNsfw(value);
            }
          })
        }
        Text($r('app.string.browse_set_nsfw_hint'))
          .fontSize(12)
          .fontColor(this.pal.sub)
          .margin({ left: 20, top: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }
}

// 浏览设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct BrowseSettingsPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.browse_set_title') })
        BrowseSettingsContent()
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
export function BrowseSettingsBuilder() {
  BrowseSettingsPage()
}
