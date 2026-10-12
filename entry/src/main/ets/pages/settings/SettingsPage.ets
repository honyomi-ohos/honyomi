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
        PageHeader({ title: $r('app.string.settings_title') })
        Scroll() {
          Column({ space: 12 }) {
            PrefGroup({ groupTitle: $r('app.string.settings_general') }) {
              SelectRow({
                title: $r('app.string.settings_start_tab'),
                value: this.startTabLabel,
                options: this.tabLabels,
                onSelect: (value: string): void => {
                  const idx = this.tabLabels.indexOf(value);
                  if (idx >= 0) {
                    Settings.setStartTab(idx);
                    this.startTabLabel = value;
                  }
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.settings_personalization') }) {
              IconRow({
                title: $r('app.string.appearance_title'),
                icon: 'palette',
                onTap: (): void => {
                  this.pathStack.pushPathByName('Appearance', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: $r('app.string.settings_library'),
                icon: 'collections_bookmark',
                onTap: (): void => {
                  this.pathStack.pushPathByName('LibrarySettings', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: $r('app.string.settings_reader'),
                icon: 'image',
                onTap: (): void => {
                  this.pathStack.pushPathByName('ReaderSettings', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: $r('app.string.player_set_title'),
                icon: 'play_arrow',
                onTap: (): void => {
                  this.pathStack.pushPathByName('PlayerSettings', null);
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.settings_data') }) {
              IconRow({
                title: $r('app.string.settings_downloads'),
                icon: 'download',
                onTap: (): void => {
                  this.pathStack.pushPathByName('DownloadsSettings', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: $r('app.string.settings_browse'),
                icon: 'explore',
                onTap: (): void => {
                  this.pathStack.pushPathByName('BrowseSettings', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: $r('app.string.data_storage_title'),
                icon: 'storage',
                onTap: (): void => {
                  this.pathStack.pushPathByName('DataStorage', null);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              IconRow({
                title: $r('app.string.settings_advanced'),
                icon: 'settings',
                onTap: (): void => {
                  this.pathStack.pushPathByName('Advanced', null);
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.appearance_other') }) {
              IconRow({
                title: $r('app.string.settings_about'),
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
