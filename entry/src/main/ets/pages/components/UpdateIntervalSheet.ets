// 更新间隔选择弹层（对齐 Mihon SetIntervalDialog / MangaActionRow 更新间隔入口）：
// 单选列表展示候选间隔，点击即选中并回调宿主页落库（MangaRepo.setUpdateInterval）。
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';

// 更新间隔候选项：hours 为小时数，label 为展示文案
export interface IntervalOption {
  hours: number;
  label: string;
}

// 更新间隔值 ↔ 文案映射（0=跟随全局 -1=永不 >0=间隔小时数）
export class UpdateIntervals {
  // 跟随全局刷新设置
  static readonly GLOBAL: number = 0;
  // 从不参与全局刷新
  static readonly NEVER: number = -1;

  // 候选列表（对齐 Mihon UpdateStrategy/SetIntervalDialog 档位）
  static options(): IntervalOption[] {
    const list: IntervalOption[] = [
      { hours: UpdateIntervals.GLOBAL, label: '跟随全局' },
      { hours: UpdateIntervals.NEVER, label: '永不' },
      { hours: 1, label: '每小时' },
      { hours: 6, label: '每 6 小时' },
      { hours: 12, label: '每 12 小时' },
      { hours: 24, label: '每天' },
      { hours: 48, label: '每 2 天' },
      { hours: 72, label: '每 3 天' },
      { hours: 168, label: '每周' },
      { hours: 336, label: '每 2 周' },
      { hours: 720, label: '每月' },
    ];
    return list;
  }

  // 间隔值 → 展示文案；非预设值按小时数回退描述
  static label(hours: number): string {
    const opts = UpdateIntervals.options();
    for (const opt of opts) {
      if (opt.hours === hours) {
        return opt.label;
      }
    }
    if (hours === UpdateIntervals.GLOBAL) {
      return '跟随全局';
    }
    if (hours === UpdateIntervals.NEVER) {
      return '永不';
    }
    return `每 ${hours} 小时`;
  }
}

// 更新间隔选择弹层：当前值高亮 + 勾选指示，点击选项立即回调
@Component
export struct UpdateIntervalSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 宿主页当前间隔值（小时）
  initHours: number = 0;
  @State selectedHours: number = 0;
  onPicked: (hours: number) => void = (_hours: number) => {
  };
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    this.selectedHours = this.initHours;
  }

  build() {
    Column() {
      Text('更改更新间隔')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .width('100%')
        .padding({ left: 20, right: 20, top: 2, bottom: 10 })
      Scroll() {
        Column() {
          ForEach(UpdateIntervals.options(), (opt: IntervalOption) => {
            Row() {
              Text(opt.label)
                .fontSize(16)
                .fontColor(this.selectedHours === opt.hours ? this.pal.primary : this.pal.text)
                .layoutWeight(1)
                .maxLines(1)
              if (this.selectedHours === opt.hours) {
                AppIcon({ name: 'done', iconSize: 22, tint: this.pal.primary })
              }
            }
            .width('100%')
            .height(52)
            .padding({ left: 20, right: 20 })
            .borderRadius(14)
            .backgroundColor(this.selectedHours === opt.hours ? this.pal.primarySoft : this.pal.chip)
            .margin({ bottom: 8 })
            .onClick(() => {
              this.selectedHours = opt.hours;
              this.onPicked(opt.hours);
            })
          }, (opt: IntervalOption, idx: number) => `interval-${idx}-${opt.hours}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 16 })
    .backgroundColor(this.pal.bg)
  }
}
