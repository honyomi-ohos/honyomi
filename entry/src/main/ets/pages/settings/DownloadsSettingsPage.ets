import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, PrefSwitchRow } from '../components/Prefs';

// 下载设置内容（仅 Wi-Fi 为占位，后续接入网络类型检测）
@Component
export struct DownloadsSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    Scroll() {
      Column() {
        PrefGroup({ groupTitle: $r('app.string.dl_set_network') }) {
          PrefSwitchRow({
            title: $r('app.string.dl_set_wifi_only'),
            initValue: Settings.getDownloadWifiOnly(),
            apply: (value: boolean): void => {
              Settings.setDownloadWifiOnly(value);
            }
          })
        }

        Text($r('app.string.dl_set_wifi_only_hint'))
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

// 下载设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct DownloadsSettingsPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.dl_set_title') })
        DownloadsSettingsContent()
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
export function DownloadsSettingsBuilder() {
  DownloadsSettingsPage()
}
