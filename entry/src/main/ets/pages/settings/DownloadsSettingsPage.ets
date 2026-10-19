import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { AppKeys } from '../../common/AppKeys';
import { Util } from '../../common/Util';
import { Bp } from '../../common/Breakpoint';
import { DownloadService } from '../../data/DownloadService';
import { BtFlow } from '../../data/BtFlow';
import { BtComponentInstaller } from '../../common/BtComponentInstaller';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, PrefSelectRow, PrefSliderRow, PrefSwitchRow } from '../components/Prefs';
import { AppIcon } from '../components/AppIcon';

// "阅读后自动删除"选项值：-1 禁用，1-5 倒数第 N 个已读章节
const REMOVE_SLOTS_VALUES: number[] = [-1, 1, 2, 3, 4, 5];
// "阅读时预下载"选项值：0 禁用，1/2/3/5/10 章
const AHEAD_VALUES: number[] = [0, 1, 2, 3, 5, 10];
// BT 引擎选择：每次询问 / 内置引擎 / 系统应用
const BT_ENGINE_VALUES: string[] = ['ask', 'module', 'system'];
// BT 限速滑条索引映射值（KB/s，0 = 不限）
const BT_LIMIT_VALUES: number[] = [0, 512, 1024, 2048, 4096, 8192, 16384];

// 下载设置内容（对齐 Mihon SettingsDownloadScreen）：
// 仅 Wi-Fi / CBZ / 拆长图 / 并发下载数 / 删除策略 / 自动下载 / 阅读预下载
@Component
export struct DownloadsSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  // 额外 tracker 编辑草稿（bindSheet 内 TextArea 双向暂存，保存时落库）
  @State showTrackerSheet: boolean = false;
  @State trackerDraft: string = '';
  // 内置引擎组件缺失（引擎选"内置"时显示安装引导行）
  @State btModuleMissing: boolean = false;

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

        PrefGroup({ groupTitle: $r('app.string.bt_set_group') }) {
          PrefSelectRow({
            title: $r('app.string.bt_set_engine'),
            options: this.btEngineOptions(),
            selectedIndex: this.btEngineIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setBtEngineChoice(BT_ENGINE_VALUES[index]);
              this.refreshBtState();
            }
          })
          if (this.btModuleMissing) {
            Divider().color(this.pal.divider).margin({ left: 16 })
            // 引擎选"内置"但组件缺失：点击重新拉起 Index 的安装引导弹窗
            Row() {
              AppIcon({ name: 'download', iconSize: 22 })
                .margin({ right: 12 })
              Column() {
                Text($r('app.string.bt_engine_module_missing'))
                  .fontSize(16)
                  .fontColor(this.pal.text)
                  .maxLines(1)
                Text($r('app.string.bt_engine_module_missing_sub'))
                  .fontSize(12)
                  .fontColor(this.pal.sub)
                  .maxLines(2)
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Text($r('app.string.bt_engine_install'))
                .fontSize(14)
                .fontColor(this.pal.primary)
                .maxLines(1)
            }
            .width('100%')
            .constraintSize({ minHeight: 52 })
            .padding({ left: 16, right: 12, top: 10, bottom: 10 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              AppStorage.setOrCreate(AppKeys.BT_COMPONENT_ASK, true);
            })
          }
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.bt_set_progressive'),
            subtitle: $r('app.string.bt_set_progressive_sub'),
            initValue: Settings.getBtProgressive(),
            apply: (value: boolean): void => {
              Settings.setBtProgressive(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.bt_set_speed_limits') }) {
          PrefSliderRow({
            title: $r('app.string.bt_set_download_limit'),
            initValue: this.btLimitIndex(Settings.getBtDownloadLimitKb()),
            minValue: 0,
            maxValue: BT_LIMIT_VALUES.length - 1,
            stepValue: 1,
            valueText: (v: number): ResourceStr => this.btLimitText(BT_LIMIT_VALUES[v]),
            apply: (v: number): void => {
              Settings.setBtDownloadLimitKb(BT_LIMIT_VALUES[v]);
              BtFlow.applyLimitsLive();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSliderRow({
            title: $r('app.string.bt_set_upload_limit'),
            initValue: this.btLimitIndex(Settings.getBtUploadLimitKb()),
            minValue: 0,
            maxValue: BT_LIMIT_VALUES.length - 1,
            stepValue: 1,
            valueText: (v: number): ResourceStr => this.btLimitText(BT_LIMIT_VALUES[v]),
            apply: (v: number): void => {
              Settings.setBtUploadLimitKb(BT_LIMIT_VALUES[v]);
              BtFlow.applyLimitsLive();
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          Row() {
            Column() {
              Text($r('app.string.bt_set_extra_trackers'))
                .fontSize(16)
                .fontColor(this.pal.text)
                .maxLines(1)
              Text($r('app.string.bt_set_extra_trackers_sub'))
                .fontSize(12)
                .fontColor(this.pal.sub)
                .maxLines(2)
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.trackerCountText())
              .fontSize(14)
              .fontColor(this.pal.sub)
              .maxLines(1)
              .margin({ left: 8 })
            AppIcon({ name: 'keyboard_arrow_right', iconSize: 20 })
              .margin({ left: 4 })
          }
          .width('100%')
          .constraintSize({ minHeight: 52 })
          .padding({ left: 16, right: 12, top: 10, bottom: 10 })
          .alignItems(VerticalAlign.Center)
          .bindSheet($$this.showTrackerSheet, this.trackerSheetBuilder(), {
            preferType: Bp.sheetType(this.windowW),
            width: Bp.sheetWidth(this.windowW),
            height: SheetSize.FIT_CONTENT,
            title: { title: $r('app.string.bt_set_extra_trackers') },
            detents: [SheetSize.FIT_CONTENT],
            dragBar: true,
            showClose: false,
            blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
          })
          .onClick(() => {
            this.trackerDraft = Settings.getBtExtraTrackers();
            this.showTrackerSheet = true;
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  aboutToAppear(): void {
    this.refreshBtState();
  }

  // 引擎选择为"内置"且组件未安装时提示安装（选择行切换后即时刷新）
  private refreshBtState(): void {
    this.btModuleMissing = Settings.getBtEngineChoice() === 'module' && !BtComponentInstaller.isInstalled();
  }

  private btEngineOptions(): ResourceStr[] {
    return [
      $r('app.string.bt_engine_ask'),
      $r('app.string.bt_engine_module'),
      $r('app.string.bt_engine_system')
    ];
  }

  private btEngineIndex(): number {
    const idx = BT_ENGINE_VALUES.indexOf(Settings.getBtEngineChoice());
    return idx >= 0 ? idx : 0;
  }

  // 限速 KB → 滑条索引（未匹配值取不大于它的最近档位）
  private btLimitIndex(kb: number): number {
    let idx = 0;
    for (let i = 0; i < BT_LIMIT_VALUES.length; i += 1) {
      if (BT_LIMIT_VALUES[i] <= kb) {
        idx = i;
      }
    }
    return idx;
  }

  private btLimitText(kb: number): ResourceStr {
    if (kb <= 0) {
      return $r('app.string.bt_limit_unlimited');
    }
    if (kb < 1024) {
      return $r('app.string.bt_limit_kb', kb);
    }
    return $r('app.string.bt_limit_mb', kb / 1024);
  }

  private trackerCountText(): string {
    const n = BtFlow.extraTrackerList().length;
    if (n === 0) {
      return Util.resStr(this.getUIContext(), $r('app.string.bt_trackers_none'));
    }
    return Util.resStr(this.getUIContext(), $r('app.string.bt_trackers_n', n));
  }

  @Builder
  trackerSheetBuilder() {
    Column({ space: 12 }) {
      TextArea({ text: this.trackerDraft, placeholder: $r('app.string.bt_set_extra_trackers_hint') })
        .fontSize(14)
        .height(160)
        .width('100%')
        .onChange((value: string) => {
          this.trackerDraft = value;
        })
      Button($r('app.string.common_save'))
        .width('100%')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .backgroundColor(this.pal.primary)
        .onClick(() => {
          Settings.setBtExtraTrackers(this.trackerDraft);
          this.showTrackerSheet = false;
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
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
