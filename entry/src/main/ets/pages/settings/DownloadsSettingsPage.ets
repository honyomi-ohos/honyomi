import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SwitchRow } from '../components/Prefs';

// 下载设置（仅 Wi-Fi 为占位，后续接入网络类型检测）
@Component
export struct DownloadsSettingsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State wifiOnly: boolean = false;

  aboutToAppear(): void {
    this.wifiOnly = Settings.getDownloadWifiOnly();
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '下载' })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: '网络' }) {
              SwitchRow({
                title: '仅 Wi-Fi 时下载',
                isOn: this.wifiOnly,
                onChange: (value: boolean): void => {
                  this.wifiOnly = value;
                  Settings.setDownloadWifiOnly(value);
                }
              })
            }
            Text('说明：当前版本此开关为预留项，网络类型检测将在后续版本提供')
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
