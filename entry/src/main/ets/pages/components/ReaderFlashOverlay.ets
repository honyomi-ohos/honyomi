// 墨水屏刷新闪屏遮罩（对齐 Mihon DisplayRefreshHost）：
// 常驻全屏且不拦截任何触摸（HitTestMode.None），关闭时完全透明；
// 宿主每次真实翻页将 flashTick +1，组件按“每 N 页”计数决定是否闪屏，
// 颜色序列：white=白、black=黑、both=白转黑，前后两段各占时长一半
@Component
export struct ReaderFlashOverlay {
  // 宿主每次真实翻页 +1（@Watch 触发评估）
  @Prop @Watch('onTick') flashTick: number = 0;
  // 墨水屏闪屏总开关（避免与通用属性 enabled 命名冲突）
  @Prop flashEnabled: boolean = false;
  // 闪屏颜色：white | black | both
  @Prop flashColor: string = 'white';
  // 闪屏总时长（毫秒）
  @Prop flashDurationMs: number = 150;
  // 每 N 页闪一次（间隔变化时重置计数，对齐 Mihon setInterval 语义）
  @Prop @Watch('onIntervalChanged') flashInterval: number = 1;
  @State private visible: boolean = false;
  @State private phaseColor: string = '#FFFFFFFF';
  private timesCalled: number = 0;
  private timerId: number = -1;

  aboutToDisappear(): void {
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private onIntervalChanged(): void {
    this.timesCalled = 0;
  }

  private onTick(): void {
    if (!this.flashEnabled) {
      return;
    }
    const interval: number = this.flashInterval > 0 ? this.flashInterval : 1;
    const shouldFlash: boolean = this.timesCalled % interval === 0;
    this.timesCalled += 1;
    if (!shouldFlash) {
      return;
    }
    const halfMs: number = Math.max(16, Math.floor(this.flashDurationMs / 2));
    const mode: string = this.flashColor;
    this.clearTimer();
    this.phaseColor = mode === 'black' ? '#FF000000' : '#FFFFFFFF';
    this.visible = true;
    this.timerId = setTimeout((): void => {
      if (mode === 'both') {
        this.phaseColor = '#FF000000';
      }
      this.timerId = setTimeout((): void => {
        this.visible = false;
        this.timerId = -1;
      }, halfMs);
    }, halfMs);
  }

  build() {
    Stack() {
      if (this.visible) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.phaseColor)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
