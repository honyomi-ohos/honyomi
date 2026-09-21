import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, IconRow, SelectRow } from '../components/Prefs';

const TAB_COUNT: number = 5;

// 设置中心主页：常规 + 各分类入口
@Component
export struct SettingsPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State tabLabels: string[] = [];
  @State startTabLabel: string = '';

  aboutToAppear(): void {
    this.tabLabels = [
      Util.resStr(this.getUIContext(), $r('app.string.settings_tab_library')),
      Util.resStr(this.getUIContext(), $r('app.string.settings_tab_updates')),
      Util.resStr(this.getUIContext(), $r('app.string.settings_tab_history')),
      Util.resStr(this.getUIContext(), $r('app.string.settings_tab_browse')),
      Util.resStr(this.getUIContext(), $r('app.string.settings_tab_more'))
    ];
    const idx = Settings.getStartTab();
    this.startTabLabel = idx >= 0 && idx < this.tabLabels.length ? this.tabLabels[idx] : this.tabLabels[0];
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '设置' })
        Scroll() {
          Column({ space: 12 }) {
            PrefGroup({ groupTitle: '常规' }) {
              SelectRow({
                title: '启动页面',
                value: this.startTabLabel,
                options: TAB_LABELS,
                onSelect: (value: string): void => {
                  const idx = TAB_LABELS.indexOf(value);
                  if (idx >= 0) {
                    Settings.setStartTab(idx);
                    this.startTabLabel = value;
                  }
                }
              })
            }

            PrefGroup({ groupTitle: '个性化' }) {
              IconRow({
                title: '外观',
                icon: 'palette',
                onTap: (): void => {
                  this.pathStack.pushPathByName('Appearance', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: '书架',
                icon: 'collections_bookmark',
                onTap: (): void => {
                  this.pathStack.pushPathByName('LibrarySettings', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: '阅读器',
                icon: 'image',
                onTap: (): void => {
                  this.pathStack.pushPathByName('ReaderSettings', null);
                }
              })
            }

            PrefGroup({ groupTitle: '数据' }) {
              IconRow({
                title: '下载',
                icon: 'download',
                onTap: (): void => {
                  this.pathStack.pushPathByName('DownloadsSettings', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: '浏览',
                icon: 'explore',
                onTap: (): void => {
                  this.pathStack.pushPathByName('BrowseSettings', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: '高级',
                icon: 'settings',
                onTap: (): void => {
                  this.pathStack.pushPathByName('Advanced', null);
                }
              })
            }

            PrefGroup({ groupTitle: '其他' }) {
              IconRow({
                title: '关于',
                icon: 'info',
                onTap: (): void => {
                  this.pathStack.pushPathByName('About', null);
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
