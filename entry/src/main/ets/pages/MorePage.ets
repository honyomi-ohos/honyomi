import { common } from '@kit.AbilityKit';
import { ThemePalette } from '../common/Theme';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { PrefGroup, SwitchRow, IconRow } from './components/Prefs';

const HELP_URL: string = 'https://mihon.app/docs/guides/troubleshooting/';

// 更多页（对齐 Mihon MoreScreen）：
// Logo 头部 + 全局开关（仅下载/无痕，带副标题）+ 功能入口（含数据与存储一级直达）
// + 设置 / 支持我们 / 关于 / 帮助
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
            Text('Honyomi')
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

          // 全局开关（带副标题，对齐原版 SwitchPreferenceWidget）
          PrefGroup() {
            SwitchRow({
              icon: 'cloud_off',
              title: $r('app.string.more_downloaded_only'),
              subtitle: $r('app.string.more_downloaded_only_summary'),
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
              subtitle: $r('app.string.more_incognito_summary'),
              isOn: this.incognito,
              onChange: (value: boolean): void => {
                this.incognito = value;
                Settings.setIncognito(value);
              }
            })
          }

          // 功能入口：下载队列 / 分类 / 统计 / 数据与存储
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
              title: $r('app.string.stats_title'),
              icon: 'query_stats',
              onTap: (): void => {
                this.pathStack.pushPathByName('Stats', null);
              }
            })
            Divider().color(this.pal.divider).margin({ left: 52 })
            IconRow({
              title: $r('app.string.data_storage_title'),
              icon: 'storage',
              onTap: (): void => {
                this.pathStack.pushPathByName('DataStorage', null);
              }
            })
          }

          // 设置 / 支持我们 / 关于 / 帮助
          PrefGroup() {
            IconRow({
              title: $r('app.string.more_settings'),
              icon: 'settings',
              onTap: (): void => {
                this.pathStack.pushPathByName('Settings', null);
              }
            })
            Divider().color(this.pal.divider).margin({ left: 52 })
            IconRow({
              title: $r('app.string.more_support'),
              icon: 'volunteer_activism',
              onTap: (): void => {
                this.pathStack.pushPathByName('Support', null);
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
            Divider().color(this.pal.divider).margin({ left: 52 })
            IconRow({
              title: $r('app.string.more_help'),
              icon: 'help',
              onTap: (): void => {
                const context = Util.hostAbilityContext(this.getUIContext());
                Util.openUrl(context, HELP_URL);
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
