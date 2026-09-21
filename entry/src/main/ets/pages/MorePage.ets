import { ThemePalette } from '../common/Theme';
import { Settings } from '../common/Settings';
import { PrefGroup, SwitchRow, IconRow } from './components/Prefs';

// 更多页：Logo 头部 + 全局开关（仅下载/无痕）+ 功能入口
@Component
export struct MorePage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('downloadedOnly') downloadedOnly: boolean = false;
  @StorageProp('incognito') incognito: boolean = false;

  build() {
    Column() {
      Text($r('app.string.more_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column({ space: 12 }) {
          // Logo 头部
          Column() {
            Image($r('app.media.startIcon'))
              .width(72)
              .height(72)
              .borderRadius(16)
            Text('MihonHarmony')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.text)
              .margin({ top: 10 })
            Text($r('app.string.more_version', '1.0.0'))
              .fontSize(12)
              .fontColor(this.pal.sub)
              .margin({ top: 2 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 16 })

          // 全局开关
          PrefGroup() {
            SwitchRow({
              icon: 'cloud_off',
              title: $r('app.string.more_downloaded_only'),
              isOn: this.downloadedOnly,
              onChange: (value: boolean): void => {
                this.downloadedOnly = value;
                Settings.setDownloadedOnly(value);
              }
            })
            Divider().color(this.pal.divider).margin({ left: 52 })
            SwitchRow({
              icon: 'visibility_off',
              title: $r('app.string.more_incognito'),
              isOn: this.incognito,
              onChange: (value: boolean): void => {
                this.incognito = value;
                Settings.setIncognito(value);
              }
            })
          }

          // 功能入口
          PrefGroup() {
            IconRow({
              title: $r('app.string.more_downloads'),
              icon: 'download',
              onTap: (): void => {
                this.pathStack.pushPathByName('Downloads', null);
              }
            })
            Divider().color(this.pal.divider).margin({ left: 52 })
            IconRow({
              title: $r('app.string.more_categories'),
              icon: 'label',
              onTap: (): void => {
                this.pathStack.pushPathByName('Categories', null);
              }
            })
            Divider().color(this.pal.divider).margin({ left: 52 })
            IconRow({
              title: $r('app.string.more_settings'),
              icon: 'settings',
              onTap: (): void => {
                this.pathStack.pushPathByName('Settings', null);
              }
            })
            Divider().color(this.pal.divider).margin({ left: 52 })
            IconRow({
              title: $r('app.string.more_about'),
              icon: 'info',
              onTap: (): void => {
                this.pathStack.pushPathByName('About', null);
              }
            })
          }

          // 插件入口（P2 将迁移至浏览页）
          PrefGroup() {
            IconRow({
              title: $r('app.string.more_plugins'),
              icon: 'travel_explore',
              onTap: (): void => {
                this.pathStack.pushPathByName('Plugins', null);
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
      .contentEndOffset(this.navBarH + 76)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }
}
