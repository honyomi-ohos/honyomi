// 翻页/覆盖变换数组写入器：页面 @State 数组只做元素级 set-if-changed 写入
// （不替换数组引用，元素赋值可被 @State 观察），越界索引静默忽略
export class FlipTransformDriver {
  // 单通道 set-if-changed
  static setIfChanged(arr: number[], index: number, value: number): void {
    if (index < 0 || index >= arr.length) {
      return;
    }
    if (arr[index] !== value) {
      arr[index] = value;
    }
  }

  // 三通道批量写入（小说 位移/角度/层级 或 漫画 cover x/y/z）
  static setXYZ(xArr: number[], yArr: number[], zArr: number[],
    index: number, x: number, y: number, z: number): void {
    FlipTransformDriver.setIfChanged(xArr, index, x);
    FlipTransformDriver.setIfChanged(yArr, index, y);
    FlipTransformDriver.setIfChanged(zArr, index, z);
  }

  // 双页仿真半页翻转角（左右半页独立通道）
  static setHalf(angleLArr: number[], angleRArr: number[],
    index: number, angleL: number, angleR: number): void {
    FlipTransformDriver.setIfChanged(angleLArr, index, angleL);
    FlipTransformDriver.setIfChanged(angleRArr, index, angleR);
  }

  // 覆盖动画平移量：以负向 translate 抵消默认位移
  static coverTranslate(position: number, mainAxisLength: number): number {
    return -position * mainAxisLength;
  }
}
