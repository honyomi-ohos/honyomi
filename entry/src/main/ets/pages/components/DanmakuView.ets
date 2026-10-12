import { DanmakuItem } from '../../data/DanmakuService';

// 活跃弹幕：含轨道、实测文本宽度与激活时的播放位置
class ActiveDm {
  item: DanmakuItem = new DanmakuItem();
  textW: number = 0;
  track: number = 0;
  startMs: number = 0;
}

// 父组件与弹幕视图的通信桥（注入 items / 重置）
export class DanmakuController {
  setItemsFn: (items: DanmakuItem[]) => void = (_items: DanmakuItem[]) => {
  };
  resetFn: () => void = (): void => {
  };

  setItems(items: DanmakuItem[]): void {
    this.setItemsFn(items);
  }

  reset(): void {
    this.resetFn();
  }
}

// 弹幕渲染组件：Canvas + 40ms 自驱帧循环，位置由 positionProvider 回调驱动（暂停即冻结）
@Component
export struct DanmakuView {
  @Prop @Watch('onDmSettingChanged') dmEnabled: boolean = true;
  @Prop @Watch('onDmSettingChanged') fontVp: number = 16;
  @Prop @Watch('onDmSettingChanged') opacityPct: number = 80;
  @Prop @Watch('onDmSettingChanged') areaPct: number = 50;
  @Prop @Watch('onDmSettingChanged') durSec: number = 10;
  controller: DanmakuController = new DanmakuController();
  positionProvider: () => number = (): number => 0;
  private renderSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderSettings);
  private items: DanmakuItem[] = [];
  private actives: ActiveDm[] = [];
  private cursor: number = 0;
  private lastPosMs: number = -1;
  private ticker: number = -1;
  private canvasW: number = 0;
  private canvasH: number = 0;
  private fontPx: number = 16;
  private scrollLast: ActiveDm[] = [];
  private topEnds: number[] = [];
  private bottomEnds: number[] = [];

  aboutToAppear(): void {
    this.controller.setItemsFn = (items: DanmakuItem[]): void => {
      this.items = items;
      this.resetTo(this.positionProvider());
    };
    this.controller.resetFn = (): void => {
      this.resetTo(this.positionProvider());
    };
    this.fontPx = Math.max(9, Math.floor(this.getUIContext().vp2px(this.fontVp)));
    this.ticker = setInterval(() => {
      this.tick();
    }, 40);
  }

  aboutToDisappear(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  private onDmSettingChanged(): void {
    this.fontPx = Math.max(9, Math.floor(this.getUIContext().vp2px(this.fontVp)));
    this.softReset();
    this.tick();
  }

  private softReset(): void {
    this.actives = [];
    this.scrollLast = [];
    this.topEnds = [];
    this.bottomEnds = [];
  }

  private resetTo(pos: number): void {
    this.softReset();
    this.cursor = DanmakuView.firstIndexAfter(this.items, pos);
  }

  private static firstIndexAfter(items: DanmakuItem[], pos: number): number {
    let lo: number = 0;
    let hi: number = items.length;
    while (lo < hi) {
      const mid: number = (lo + hi) >> 1;
      if (items[mid].timeMs <= pos) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  private tick(): void {
    const pos: number = this.positionProvider();
    if (!this.dmEnabled) {
      if (this.actives.length > 0 && this.canvasW > 0) {
        this.softReset();
        this.ctx.clearRect(0, 0, this.canvasW, this.canvasH);
      }
      this.lastPosMs = pos;
      return;
    }
    if (this.lastPosMs < 0) {
      this.lastPosMs = pos;
    }
    // 位置回跳/大幅前跳（seek）时重置
    if (pos < this.lastPosMs - 400 || pos > this.lastPosMs + 2500) {
      this.resetTo(pos);
    }
    this.lastPosMs = pos;
    while (this.cursor < this.items.length && this.items[this.cursor].timeMs <= pos) {
      this.activate(this.items[this.cursor], pos);
      this.cursor += 1;
    }
    this.draw(pos);
  }

  private activate(item: DanmakuItem, pos: number): void {
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    const a: ActiveDm = new ActiveDm();
    a.item = item;
    a.startMs = pos;
    this.ctx.font = `${this.fontPx}px sans-serif`;
    const metrics: TextMetrics = this.ctx.measureText(item.text);
    a.textW = metrics.width;
    const trackH: number = this.fontPx * 1.5;
    if (item.mode === 1) {
      const areaH: number = this.canvasH * this.areaPct / 100;
      const maxTrack: number = Math.max(1, Math.floor(areaH / trackH));
      for (let t: number = 0; t < maxTrack; t++) {
        const last: ActiveDm | undefined = this.scrollLast[t];
        if (last === undefined || this.scrollX(last, pos) + last.textW < this.canvasW) {
          a.track = t;
          this.scrollLast[t] = a;
          this.actives.push(a);
          return;
        }
      }
      return;
    }
    const ends: number[] = item.mode === 5 ? this.topEnds : this.bottomEnds;
    const maxFixed: number = Math.max(1, Math.min(6, Math.floor(this.canvasH * 0.5 / trackH)));
    for (let t: number = 0; t < maxFixed; t++) {
      const end: number | undefined = ends[t];
      if (end === undefined || end <= pos) {
        a.track = t;
        ends[t] = pos + 5000;
        this.actives.push(a);
        return;
      }
    }
  }

  private scrollX(a: ActiveDm, pos: number): number {
    const durMs: number = this.durSec * 1000;
    return this.canvasW - (this.canvasW + a.textW) * (pos - a.startMs) / durMs;
  }

  private draw(pos: number): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    ctx.clearRect(0, 0, this.canvasW, this.canvasH);
    if (this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    ctx.globalAlpha = this.opacityPct / 100;
    ctx.font = `${this.fontPx}px sans-serif`;
    ctx.textAlign = 'start';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = Math.max(2, this.fontPx / 7);
    ctx.strokeStyle = 'rgba(0,0,0,0.8)';
    const trackH: number = this.fontPx * 1.5;
    const kept: ActiveDm[] = [];
    for (let i: number = 0; i < this.actives.length; i++) {
      const a: ActiveDm = this.actives[i];
      if (a.item.mode === 1) {
        const x: number = this.scrollX(a, pos);
        if (x + a.textW < 0) {
          continue;
        }
        this.paint(a.item, x, a.track * trackH + trackH / 2 + 2);
      } else {
        if (pos - a.startMs > 5000) {
          continue;
        }
        const x: number = (this.canvasW - a.textW) / 2;
        if (a.item.mode === 5) {
          this.paint(a.item, x, a.track * trackH + trackH / 2 + 2);
        } else {
          this.paint(a.item, x, this.canvasH - (a.track + 1) * trackH + trackH / 2);
        }
      }
      kept.push(a);
    }
    this.actives = kept;
  }

  private paint(item: DanmakuItem, x: number, y: number): void {
    this.ctx.strokeText(item.text, x, y);
    this.ctx.fillStyle = DanmakuView.hexColor(item.color);
    this.ctx.fillText(item.text, x, y);
  }

  private static hexColor(color: number): string {
    return `#${(color & 0xFFFFFF).toString(16).toUpperCase().padStart(6, '0')}`;
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onAreaChange((_old: Area, newArea: Area) => {
        const w: Length = newArea.width;
        const h: Length = newArea.height;
        const pxW: number = typeof w === 'number' ? Math.floor(this.getUIContext().vp2px(w)) : 0;
        const pxH: number = typeof h === 'number' ? Math.floor(this.getUIContext().vp2px(h)) : 0;
        if (pxW !== this.canvasW || pxH !== this.canvasH) {
          this.canvasW = pxW;
          this.canvasH = pxH;
          this.softReset();
        }
      })
  }
}
