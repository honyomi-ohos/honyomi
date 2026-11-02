// 设置 Sheet 无状态派发器：bindSheet 的 $$ 双向同步允许系统直接关闭弹层，
// 开闭状态以页面各布尔为准；本类只集中「互斥打开/全部关闭」的派发逻辑
export class ReaderSheetStack {
  private readonly names: string[];
  private readonly apply: (name: string, open: boolean) => void;

  constructor(names: string[], apply: (name: string, open: boolean) => void) {
    this.names = names;
    this.apply = apply;
  }

  // 互斥打开：先全部关闭再打开目标（避免多个 bindSheet 叠加）
  open(name: string): void {
    this.closeAll();
    this.apply(name, true);
  }

  closeAll(): void {
    for (let i = 0; i < this.names.length; i++) {
      this.apply(this.names[i], false);
    }
  }
}
