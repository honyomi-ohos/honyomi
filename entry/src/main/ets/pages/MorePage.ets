import { ThemePalette } from '../common/Theme';
import { Settings } from '../common/Settings';
import { Bp } from '../common/Breakpoint';
import { AppInfo } from '../common/AppInfo';
import { IconRow, PrefGroup, SwitchRow } from './components/Prefs';

// 更多页（对齐 Mihon MoreScreen）：
// Logo 头部 + 全局开关（仅下载/无痕，带副标题）+ 功能入口（含数据与存储一级直达）
// + 设置 / 关于 / 帮助（应用内自有帮助文档，不再外链 mihon.app）
@Component
export struct MorePage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  // 页签浮动条避让高度：宽屏无页签条时为 0（Index 按断点发布）
  @StorageProp('tabPadH') tabPadH: number = 76;
  @StorageProp('downloadedOnly') downloadedOnly: boolean = false;
  @StorageProp('incognito') incognito: boolean = false;

  build() {
    this.bodyContent()
  }

  @Builder
  bodyContent() {
    Column() {
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
            Text($r('app.string.more_version', AppInfo.versionName()))
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

          // 设置 / 关于 / 帮助
          // （支持我们入口已移除：Patreon/OpenCollective 等外部捐赠引流属 AppGallery 审核敏感项）
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
                this.pathStack.pushPathByName('Help', null);
              }
            })
          }
        }
        .width('100%')
        .padding({
          left: 16 + this.inset(),
          right: 16 + this.inset(),
          bottom: 24
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .contentEndOffset(this.navBarH + this.tabPadH)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }

  // 页面主体：滚动容器全宽（滚动条贴窗口边），内容列经 contentInset 限宽居中
  private inset(): number {
    return Bp.contentInset(this.windowW);
  }
}

// 更多页顶部标题栏：抽取供 Index 挂载到 Navigation 标题栏（高度 58，含 contentInset 横向留白，不含状态栏避让）
@Component
export struct MoreHeader {
  @StorageProp('windowW') windowW: number = 0;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    Row() {
      Text($r('app.string.more_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
    }
    .width('100%')
    .height(58)
    .padding({
      left: 16 + this.inset(),
      right: 16 + this.inset()
    })
  }

  private inset(): number {
    return Bp.contentInset(this.windowW);
  }
}
