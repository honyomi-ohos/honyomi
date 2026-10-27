import { ThemePalette } from '../../common/Theme';
import { SheetPreset } from '../components/SheetPreset';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { Bp } from '../../common/Breakpoint';
import { BtFlow } from '../../data/BtFlow';
import { BtModule } from '../../data/BtModule';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, PrefSelectRow, PrefSliderRow, PrefSwitchRow } from '../components/Prefs';
import { AppIcon } from '../components/AppIcon';

// BT 引擎选择：每次询问 / 内置引擎 / 系统应用
const BT_ENGINE_VALUES: string[] = ['ask', 'module', 'system'];
// BT 限速滑条索引映射值（KB/s，0 = 不限）
const BT_LIMIT_VALUES: number[] = [0, 512, 1024, 2048, 4096, 8192, 16384];
// BT 分享率滑条索引映射值（上传/下载比值，10 = 不限）
const BT_RATIO_VALUES: number[] = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
const BT_RATIO_UNLIMITED: number = 10;

// BitTorrent 设置内容（仅 torrent 组件已安装时可见，入口由 SettingsPage 控制）：
// 引擎选择 / 边下边播 / Peer 过滤器 / 速度限制 / 额外 Tracker / 计费限上传 / 做种分享率
@Component
export struct BtSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  // 额外 tracker 编辑草稿（bindSheet 内 TextArea 双向暂存，保存时落库）
  @State showTrackerSheet: boolean = false;
  @State trackerDraft: string = '';
  // Peer 过滤规则数：BtPeerFilterPage 保存后经 AppStorage tick 通知刷新
  // （返回本页无状态变化不会重渲染，需响应式信号驱动）
  @StorageProp('btPeerFilterTick') @Watch('refreshPeerFilterCount') btPeerFilterTick: number = 0;
  @State peerFilterCount: number = 0;
  // Peer 过滤器页跳转（宿主 shell/SettingsPage 注入，两处均有可用 pathStack）
  openPeerFilter: () => void = (): void => {
  };

  aboutToAppear(): void {
    this.peerFilterCount = BtModule.peerFilterRules().length;
  }

  private refreshPeerFilterCount(): void {
    this.peerFilterCount = BtModule.peerFilterRules().length;
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.bt_set_group') }) {
          // 服务总开关：关→立即停引擎；开→不主动启动，下次 BT 使用按需启
          PrefSwitchRow({
            title: $r('app.string.bt_set_service'),
            subtitle: $r('app.string.bt_set_service_sub'),
            initValue: Settings.getBtServiceEnabled(),
            apply: (value: boolean): void => {
              Settings.setBtServiceEnabled(value);
              if (!value) {
                BtModule.stopEngine().catch((): void => {
                });
              }
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.bt_set_engine'),
            options: this.btEngineOptions(),
            selectedIndex: this.btEngineIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setBtEngineChoice(BT_ENGINE_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.bt_set_progressive'),
            subtitle: $r('app.string.bt_set_progressive_sub'),
            initValue: Settings.getBtProgressive(),
            apply: (value: boolean): void => {
              Settings.setBtProgressive(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          Row() {
            Column() {
              Text($r('app.string.bt_set_peer_filter'))
                .fontSize(16)
                .fontColor(this.pal.text)
                .maxLines(1)
              Text($r('app.string.bt_set_peer_filter_sub'))
                .fontSize(12)
                .fontColor(this.pal.sub)
                .maxLines(2)
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Text(this.peerFilterCountText())
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
          .onClick(() => {
            this.openPeerFilter();
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
          PrefSwitchRow({
            title: $r('app.string.bt_set_limit_upload_metered'),
            subtitle: $r('app.string.bt_set_limit_upload_metered_sub'),
            initValue: Settings.getBtLimitUploadOnMetered(),
            apply: (value: boolean): void => {
              Settings.setBtLimitUploadOnMetered(value);
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
          .bindSheet($$this.showTrackerSheet, this.trackerSheetBuilder(),
            SheetPreset.fit(this.windowW, {
              title: $r('app.string.bt_set_extra_trackers'),
              showClose: false
            }))
          .onClick(() => {
            this.trackerDraft = Settings.getBtExtraTrackers();
            this.showTrackerSheet = true;
          })
        }

        PrefGroup({ groupTitle: $r('app.string.bt_set_share_group') }) {
          PrefSliderRow({
            title: $r('app.string.bt_set_share_ratio'),
            initValue: this.btRatioIndex(),
            minValue: 0,
            maxValue: BT_RATIO_VALUES.length - 1,
            stepValue: 1,
            valueText: (v: number): ResourceStr => this.btRatioText(BT_RATIO_VALUES[v]),
            apply: (v: number): void => {
              Settings.setBtShareRatioLimit(BT_RATIO_VALUES[v]);
              BtFlow.applyShareRatioLive();
            }
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

  // 分享率 → 滑条索引（未匹配值取不大于它的最近档位）
  private btRatioIndex(): number {
    const ratio = Settings.getBtShareRatioLimit();
    let idx = 0;
    for (let i = 0; i < BT_RATIO_VALUES.length; i += 1) {
      if (BT_RATIO_VALUES[i] <= ratio) {
        idx = i;
      }
    }
    return idx;
  }

  private btRatioText(ratio: number): ResourceStr {
    if (ratio >= BT_RATIO_UNLIMITED) {
      return $r('app.string.bt_limit_unlimited');
    }
    return $r('app.string.bt_share_ratio_value', ratio);
  }

  private peerFilterCountText(): string {
    if (this.peerFilterCount === 0) {
      return Util.resStr(this.getUIContext(), $r('app.string.bt_peer_filter_none'));
    }
    return Util.resStr(this.getUIContext(), $r('app.string.bt_peer_filter_n', this.peerFilterCount));
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
}

// BitTorrent 设置路由壳（手机/平板窄屏 push 进入；入口仅在组件已安装时显示）
@Component
export struct BtSettingsPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 路由栈：NavDestination onReady 时从自身上下文获取（官方推荐方式）
  pathStack: NavPathStack = new NavPathStack();

  build() {
    NavGlassPage({
      title: $r('app.string.bt_set_group'),
      onReady: (ctx: NavDestinationContext): void => {
        this.pathStack = ctx.pathStack;
      }
    }) {
      Column() {
        BtSettingsContent({
          openPeerFilter: (): void => {
            this.pathStack.pushPathByName('BtPeerFilter', null);
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function BtSettingsBuilder() {
  BtSettingsPage()
}
