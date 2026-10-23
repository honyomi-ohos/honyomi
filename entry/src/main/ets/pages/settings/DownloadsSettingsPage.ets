import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { DownloadService } from '../../data/DownloadService';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, PrefSelectRow, PrefSliderRow, PrefSwitchRow } from '../components/Prefs';

// "阅读后自动删除"选项值：-1 禁用，1-5 倒数第 N 个已读章节
const REMOVE_SLOTS_VALUES: number[] = [-1, 1, 2, 3, 4, 5];
// "阅读时预下载"选项值：0 禁用，1/2/3/5/10 章
const AHEAD_VALUES: number[] = [0, 1, 2, 3, 5, 10];

// 下载设置内容（对齐 Mihon SettingsDownloadScreen）：
// 仅 Wi-Fi / CBZ / 拆长图 / 并发下载数 / 删除策略 / 自动下载 / 阅读预下载
// （BitTorrent 相关设置在独立的 BtSettingsPage，仅组件已安装时可见）
@Component
export struct DownloadsSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.dl_set_network') }) {
          PrefSwitchRow({
            title: $r('app.string.dl_set_wifi_only'),
            initValue: Settings.getDownloadWifiOnly(),
            apply: (value: boolean): void => {
              Settings.setDownloadWifiOnly(value);
              DownloadService.refreshNetworkGate();
            }
          })
        }

        Text($r('app.string.dl_set_wifi_only_hint'))
          .fontSize(12)
          .fontColor(this.pal.sub)
          .margin({ left: 20, right: 20 })
          .alignSelf(ItemAlign.Start)

        PrefGroup() {
          PrefSwitchRow({
            title: $r('app.string.dl_set_save_cbz'),
            initValue: Settings.getSaveChaptersAsCbz(),
            apply: (value: boolean): void => {
              Settings.setSaveChaptersAsCbz(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.dl_set_split_tall'),
            subtitle: $r('app.string.dl_set_split_tall_sub'),
            initValue: Settings.getSplitTallImages(),
            apply: (value: boolean): void => {
              Settings.setSplitTallImages(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.dl_set_concurrency') }) {
          PrefSliderRow({
            title: $r('app.string.dl_set_parallel_sources'),
            initValue: Settings.getDownloadParallelSourceLimit(),
            minValue: 1,
            maxValue: 10,
            stepValue: 1,
            apply: (value: number): void => {
              Settings.setDownloadParallelSourceLimit(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSliderRow({
            title: $r('app.string.dl_set_parallel_pages'),
            initValue: Settings.getDownloadParallelPageLimit(),
            minValue: 1,
            maxValue: 15,
            stepValue: 1,
            apply: (value: number): void => {
              Settings.setDownloadParallelPageLimit(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.dl_set_delete_chapters') }) {
          PrefSwitchRow({
            title: $r('app.string.dl_set_remove_marked_read'),
            initValue: Settings.getRemoveAfterMarkedAsRead(),
            apply: (value: boolean): void => {
              Settings.setRemoveAfterMarkedAsRead(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.dl_set_remove_after_read'),
            options: this.removeSlotsOptions(),
            selectedIndex: this.removeSlotsIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setRemoveAfterReadSlots(REMOVE_SLOTS_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.dl_set_remove_bookmarked'),
            initValue: Settings.getRemoveBookmarked(),
            apply: (value: boolean): void => {
              Settings.setRemoveBookmarked(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.dl_set_auto_download') }) {
          PrefSwitchRow({
            title: $r('app.string.dl_set_download_new'),
            subtitle: $r('app.string.dl_set_download_new_sub'),
            initValue: Settings.getDownloadNewChapters(),
            apply: (value: boolean): void => {
              Settings.setDownloadNewChapters(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.dl_set_skip_read_dup'),
            initValue: Settings.getDownloadNewUnreadOnly(),
            apply: (value: boolean): void => {
              Settings.setDownloadNewUnreadOnly(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.dl_set_download_ahead') }) {
          PrefSelectRow({
            title: $r('app.string.dl_set_dl_ahead'),
            options: this.aheadOptions(),
            selectedIndex: this.aheadIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setAutoDownloadWhileReading(AHEAD_VALUES[index]);
            }
          })
        }

        Text($r('app.string.dl_set_ahead_info'))
          .fontSize(12)
          .fontColor(this.pal.sub)
          .margin({ left: 20, right: 20 })
          .alignSelf(ItemAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  private removeSlotsOptions(): ResourceStr[] {
    return [
      $r('app.string.dl_set_remove_disabled'),
      $r('app.string.dl_set_remove_last_1'),
      $r('app.string.dl_set_remove_last_2'),
      $r('app.string.dl_set_remove_last_3'),
      $r('app.string.dl_set_remove_last_4'),
      $r('app.string.dl_set_remove_last_5')
    ];
  }

  private removeSlotsIndex(): number {
    const idx = REMOVE_SLOTS_VALUES.indexOf(Settings.getRemoveAfterReadSlots());
    return idx >= 0 ? idx : 0;
  }

  private aheadOptions(): ResourceStr[] {
    return [
      $r('app.string.dl_set_remove_disabled'),
      $r('app.string.dl_set_ahead_next_1'),
      $r('app.string.dl_set_ahead_next_n', 2),
      $r('app.string.dl_set_ahead_next_n', 3),
      $r('app.string.dl_set_ahead_next_n', 5),
      $r('app.string.dl_set_ahead_next_n', 10)
    ];
  }

  private aheadIndex(): number {
    const idx = AHEAD_VALUES.indexOf(Settings.getAutoDownloadWhileReading());
    return idx >= 0 ? idx : 0;
  }
}

// 下载设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct DownloadsSettingsPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavGlassPage({ title: $r('app.string.dl_set_title') }) {
      Column() {
        DownloadsSettingsContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function DownloadsSettingsBuilder() {
  DownloadsSettingsPage()
}
