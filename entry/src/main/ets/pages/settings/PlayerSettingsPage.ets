import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, SelectRow, SwitchRow } from '../components/Prefs';

const SPEED_VALUES: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const DM_FONT_VALUES: number[] = [12, 14, 16, 18, 20];
const DM_OPACITY_VALUES: number[] = [30, 50, 80, 100];
const DM_AREA_VALUES: number[] = [25, 50, 75, 100];
const DM_DUR_VALUES: number[] = [12, 10, 8, 6];

// 播放器设置：默认倍速/自动连播 + 弹幕开关/字号/透明度/显示区域/速度
@Component
export struct PlayerSettingsPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State speedLabelVal: string = '';
  @State autoNext: boolean = true;
  @State danmakuOn: boolean = true;
  @State dmFontLabel: string = '';
  @State dmOpacityLabel: string = '';
  @State dmAreaLabel: string = '';
  @State dmDurLabel: string = '';
  private speedLabels: string[] = [];

  aboutToAppear(): void {
    this.speedLabels = [];
    for (let i = 0; i < SPEED_VALUES.length; i++) {
      this.speedLabels.push(SPEED_VALUES[i] === 1.0 ? '1.0x' : `${SPEED_VALUES[i]}x`);
    }
    this.autoNext = Settings.getVideoAutoNext();
    this.danmakuOn = Settings.getDanmakuEnabled();
    this.syncLabels();
  }

  private syncLabels(): void {
    const sp = Settings.getVideoSpeed();
    const si = SPEED_VALUES.indexOf(sp);
    this.speedLabelVal = si >= 0 ? this.speedLabels[si] : this.speedLabels[2];
    const font = Settings.getDanmakuFont();
    const fi = DM_FONT_VALUES.indexOf(font);
    this.dmFontLabel = fi >= 0 ? `${DM_FONT_VALUES[fi]}` : '16';
    const op = Settings.getDanmakuOpacityPct();
    const oi = DM_OPACITY_VALUES.indexOf(op);
    this.dmOpacityLabel = oi >= 0 ? `${DM_OPACITY_VALUES[oi]}%` : '80%';
    this.dmAreaLabel = this.areaText(Settings.getDanmakuAreaPct());
    this.dmDurLabel = this.durText(Settings.getDanmakuDurationSec());
  }

  private areaText(v: number): string {
    const labels: string[] = [
      Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_quarter')),
      Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_half')),
      Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_three_quarters')),
      Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_full'))
    ];
    const i = DM_AREA_VALUES.indexOf(v);
    return i >= 0 ? labels[i] : labels[1];
  }

  private durText(v: number): string {
    const labels: string[] = [
      Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_slow')),
      Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_normal')),
      Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_fast')),
      Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_fastest'))
    ];
    const i = DM_DUR_VALUES.indexOf(v);
    return i >= 0 ? labels[i] : labels[1];
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.player_set_title') })
        Scroll() {
          Column() {
            PrefGroup({ groupTitle: $r('app.string.player_set_playback') }) {
              SelectRow({
                title: $r('app.string.player_set_speed'),
                value: this.speedLabelVal,
                options: this.speedLabels,
                onSelect: (value: string): void => {
                  const i = this.speedLabels.indexOf(value);
                  if (i >= 0) {
                    Settings.setVideoSpeed(SPEED_VALUES[i]);
                    this.speedLabelVal = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SwitchRow({
                title: $r('app.string.player_set_auto_next'),
                subtitle: $r('app.string.player_set_auto_next_sub'),
                isOn: this.autoNext,
                onChange: (value: boolean): void => {
                  this.autoNext = value;
                  Settings.setVideoAutoNext(value);
                }
              })
            }

            PrefGroup({ groupTitle: $r('app.string.player_set_danmaku') }) {
              SwitchRow({
                title: $r('app.string.player_set_danmaku_enable'),
                isOn: this.danmakuOn,
                onChange: (value: boolean): void => {
                  this.danmakuOn = value;
                  Settings.setDanmakuEnabled(value);
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: $r('app.string.player_set_danmaku_font'),
                value: this.dmFontLabel,
                options: ['12', '14', '16', '18', '20'],
                onSelect: (value: string): void => {
                  Settings.setDanmakuFont(Number(value));
                  this.dmFontLabel = value;
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: $r('app.string.player_set_danmaku_opacity'),
                value: this.dmOpacityLabel,
                options: ['30%', '50%', '80%', '100%'],
                onSelect: (value: string): void => {
                  Settings.setDanmakuOpacityPct(Number(value.replace('%', '')));
                  this.dmOpacityLabel = value;
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: $r('app.string.player_set_danmaku_area'),
                value: this.dmAreaLabel,
                options: [
                  Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_quarter')),
                  Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_half')),
                  Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_three_quarters')),
                  Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_full'))
                ],
                onSelect: (value: string): void => {
                  const labels: string[] = [
                    Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_quarter')),
                    Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_half')),
                    Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_three_quarters')),
                    Util.resStr(this.getUIContext(), $r('app.string.danmaku_area_full'))
                  ];
                  const i = labels.indexOf(value);
                  if (i >= 0) {
                    Settings.setDanmakuAreaPct(DM_AREA_VALUES[i]);
                    this.dmAreaLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              SelectRow({
                title: $r('app.string.player_set_danmaku_speed'),
                value: this.dmDurLabel,
                options: [
                  Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_slow')),
                  Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_normal')),
                  Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_fast')),
                  Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_fastest'))
                ],
                onSelect: (value: string): void => {
                  const labels: string[] = [
                    Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_slow')),
                    Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_normal')),
                    Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_fast')),
                    Util.resStr(this.getUIContext(), $r('app.string.danmaku_speed_fastest'))
                  ];
                  const i = labels.indexOf(value);
                  if (i >= 0) {
                    Settings.setDanmakuDurationSec(DM_DUR_VALUES[i]);
                    this.dmDurLabel = value;
                  }
                }
              })
              Divider().color(this.pal.divider).margin({ left: 16 })
              Text($r('app.string.player_set_danmaku_source'))
                .fontSize(12)
                .fontColor(this.pal.sub)
                .padding({ left: 16, right: 16, top: 10, bottom: 12 })
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
