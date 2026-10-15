import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, PrefSelectRow, PrefSwitchRow } from '../components/Prefs';

const SPEED_VALUES: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const DM_FONT_VALUES: number[] = [12, 14, 16, 18, 20];
const DM_OPACITY_VALUES: number[] = [30, 50, 80, 100];
const DM_AREA_VALUES: number[] = [25, 50, 75, 100];
const DM_DUR_VALUES: number[] = [12, 10, 8, 6];

// 播放器设置内容：默认倍速/自动连播 + 弹幕开关/字号/透明度/显示区域/速度
@Component
export struct PlayerSettingsContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

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
}

// 播放器设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct PlayerSettingsPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.player_set_title') })
        PlayerSettingsContent()
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
export function PlayerSettingsBuilder() {
  PlayerSettingsPage()
}
