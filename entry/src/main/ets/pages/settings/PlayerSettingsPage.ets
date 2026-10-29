import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { DanmakuService } from '../../data/DanmakuService';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, PrefSelectRow, PrefSwitchRow } from '../components/Prefs';
import { AppIcon } from '../components/AppIcon';

const SPEED_VALUES: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const DM_FONT_VALUES: number[] = [12, 14, 16, 18, 20];
const DM_OPACITY_VALUES: number[] = [30, 50, 80, 100];
const DM_AREA_VALUES: number[] = [25, 50, 75, 100];
const DM_DUR_VALUES: number[] = [12, 10, 8, 6];
const SUB_FONT_VALUES: number[] = [12, 14, 16, 18, 20, 22, 24, 26, 28];

// 播放器设置内容：默认倍速/自动连播/跳过片头片尾 + 外挂字幕 + 弹幕开关/字号/透明度/显示区域/速度/屏蔽过滤
@Component
export struct PlayerSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 弹幕屏蔽规则（正则字符串），变更即持久化并清弹幕缓存
  @State filters: string[] = Settings.getDanmakuFilters();
  @State filterInput: string = '';

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.player_set_playback') }) {
          PrefSelectRow({
            title: $r('app.string.player_set_speed'),
            options: this.speedLabels(),
            selectedIndex: this.speedIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setVideoSpeed(SPEED_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.player_set_auto_next'),
            subtitle: $r('app.string.player_set_auto_next_sub'),
            initValue: Settings.getVideoAutoNext(),
            apply: (value: boolean): void => {
              Settings.setVideoAutoNext(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.player_set_skip_oped'),
            subtitle: $r('app.string.player_set_skip_oped_sub'),
            initValue: Settings.getVideoSkipOpEd(),
            apply: (value: boolean): void => {
              Settings.setVideoSkipOpEd(value);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.player_set_subtitle') }) {
          PrefSwitchRow({
            title: $r('app.string.player_set_subtitle_enable'),
            subtitle: $r('app.string.player_set_subtitle_enable_sub'),
            initValue: Settings.getSubtitleEnabled(),
            apply: (value: boolean): void => {
              Settings.setSubtitleEnabled(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.player_set_subtitle_font'),
            options: ['12', '14', '16', '18', '20', '22', '24', '26', '28'],
            selectedIndex: this.subFontIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setSubtitleFont(SUB_FONT_VALUES[index]);
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.player_set_danmaku') }) {
          PrefSwitchRow({
            title: $r('app.string.player_set_danmaku_enable'),
            initValue: Settings.getDanmakuEnabled(),
            apply: (value: boolean): void => {
              Settings.setDanmakuEnabled(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.player_set_danmaku_font'),
            options: ['12', '14', '16', '18', '20'],
            selectedIndex: this.fontIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setDanmakuFont(DM_FONT_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.player_set_danmaku_opacity'),
            options: ['30%', '50%', '80%', '100%'],
            selectedIndex: this.opacityIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setDanmakuOpacityPct(DM_OPACITY_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.player_set_danmaku_area'),
            options: [
              $r('app.string.danmaku_area_quarter'),
              $r('app.string.danmaku_area_half'),
              $r('app.string.danmaku_area_three_quarters'),
              $r('app.string.danmaku_area_full')
            ],
            selectedIndex: this.areaIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setDanmakuAreaPct(DM_AREA_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.player_set_danmaku_speed'),
            options: [
              $r('app.string.danmaku_speed_slow'),
              $r('app.string.danmaku_speed_normal'),
              $r('app.string.danmaku_speed_fast'),
              $r('app.string.danmaku_speed_fastest')
            ],
            selectedIndex: this.durIndex(),
            onSelectIndex: (index: number): void => {
              Settings.setDanmakuDurationSec(DM_DUR_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          Text($r('app.string.player_set_danmaku_source'))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .padding({
              left: 16,
              right: 16,
              top: 10,
              bottom: 12
            })
        }

        // 弹幕屏蔽规则（正则）：命中即隐藏，变更即清弹幕缓存
        PrefGroup({ groupTitle: $r('app.string.player_set_danmaku_filter') }) {
          ForEach(this.filters, (rule: string, idx: number) => {
            Row() {
              Text(rule)
                .fontSize(14)
                .fontColor(this.pal.text)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              AppIcon({ name: 'close', iconSize: 16, tint: this.pal.sub })
                .padding(8)
                .onClick(() => {
                  this.removeFilter(idx);
                })
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 4 })
            .alignItems(VerticalAlign.Center)
          }, (rule: string, idx: number) => `flt-${idx}-${rule}`)
          if (this.filters.length === 0) {
            Text($r('app.string.player_set_danmaku_filter_empty'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .padding({ left: 16, right: 16, top: 10 })
          }
          Row() {
            TextInput({ text: this.filterInput, placeholder: $r('app.string.player_set_danmaku_filter_hint') })
              .fontSize(14)
              .height(40)
              .fontColor(this.pal.text)
              .caretColor(this.pal.primary)
              .backgroundColor(this.pal.chip)
              .borderRadius(10)
              .padding({ left: 12, right: 8 })
              .layoutWeight(1)
              .onChange((v: string) => {
                this.filterInput = v;
              })
              .onSubmit(() => {
                this.addFilter();
              })
            Text($r('app.string.player_set_danmaku_filter_add'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal.primary)
              .padding({ left: 12, right: 4, top: 8, bottom: 8 })
              .onClick(() => {
                this.addFilter();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 8, top: 4 })
          .alignItems(VerticalAlign.Center)
          Text($r('app.string.player_set_danmaku_filter_sub'))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 4
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

  private speedLabels(): string[] {
    const labels: string[] = [];
    for (let i = 0; i < SPEED_VALUES.length; i++) {
      labels.push(SPEED_VALUES[i] === 1.0 ? '1.0x' : `${SPEED_VALUES[i]}x`);
    }
    return labels;
  }

  private speedIndex(): number {
    const i = SPEED_VALUES.indexOf(Settings.getVideoSpeed());
    return i >= 0 ? i : 2;
  }

  private fontIndex(): number {
    const i = DM_FONT_VALUES.indexOf(Settings.getDanmakuFont());
    return i >= 0 ? i : 2;
  }

  private opacityIndex(): number {
    const i = DM_OPACITY_VALUES.indexOf(Settings.getDanmakuOpacityPct());
    return i >= 0 ? i : 2;
  }

  private areaIndex(): number {
    const i = DM_AREA_VALUES.indexOf(Settings.getDanmakuAreaPct());
    return i >= 0 ? i : 1;
  }

  private durIndex(): number {
    const i = DM_DUR_VALUES.indexOf(Settings.getDanmakuDurationSec());
    return i >= 0 ? i : 1;
  }

  private subFontIndex(): number {
    const i = SUB_FONT_VALUES.indexOf(Settings.getSubtitleFont());
    return i >= 0 ? i : 3;
  }

  // ---- 弹幕屏蔽规则管理 ----

  // 新增规则：非空、不重复、合法正则；生效后清弹幕缓存
  private addFilter(): void {
    const rule: string = this.filterInput.trim();
    if (rule === '' || this.filters.indexOf(rule) >= 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.player_set_danmaku_filter_invalid'));
      return;
    }
    try {
      new RegExp(rule);
    } catch (_e) {
      Util.toastRes(this.getUIContext(), $r('app.string.player_set_danmaku_filter_invalid'));
      return;
    }
    const next: string[] = this.filters.slice(0);
    next.push(rule);
    this.applyFilters(next);
    this.filterInput = '';
  }

  private removeFilter(idx: number): void {
    const next: string[] = this.filters.slice(0);
    if (idx >= 0 && idx < next.length) {
      next.splice(idx, 1);
      this.applyFilters(next);
    }
  }

  private applyFilters(next: string[]): void {
    this.filters = next;
    Settings.setDanmakuFilters(next);
    DanmakuService.clearCache();
    Util.toastRes(this.getUIContext(), $r('app.string.player_set_danmaku_filter_applied'));
  }
}

// 播放器设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct PlayerSettingsPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavGlassPage({ title: $r('app.string.player_set_title') }) {
      Column() {
        PlayerSettingsContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function PlayerSettingsBuilder() {
  PlayerSettingsPage()
}
