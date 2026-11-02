// 自动阅读/自动翻页定时器生命周期：间隔节拍（小说 100ms 自动滚屏/翻页节拍）
// 与单次倒计时（漫画每页自动翻页），dispose 统一清理
export class AutoTurnScheduler {
  private intervalId: number = -1;
  private onceId: number = -1;

  hasInterval(): boolean {
    return this.intervalId !== -1;
  }

  // 启动间隔节拍（已在运行则保持原节拍不变）
  startInterval(intervalMs: number, onTick: () => void): void {
    if (this.intervalId !== -1) {
      return;
    }
    this.intervalId = setInterval(onTick, intervalMs);
  }

  stopInterval(): void {
    if (this.intervalId !== -1) {
      clearInterval(this.intervalId);
      this.intervalId = -1;
    }
  }

  // 单次倒计时（先取消旧倒计时再重起）
  armOnce(delayMs: number, onFire: () => void): void {
    this.cancelOnce();
    this.onceId = setTimeout(onFire, delayMs);
  }

  cancelOnce(): void {
    if (this.onceId !== -1) {
      clearTimeout(this.onceId);
      this.onceId = -1;
    }
  }

  dispose(): void {
    this.stopInterval();
    this.cancelOnce();
  }
}
