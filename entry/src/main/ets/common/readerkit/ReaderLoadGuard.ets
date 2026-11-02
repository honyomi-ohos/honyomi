// 章节加载代次守卫：begin 取号后各 await 续点用 isStale 校验，
// 连续切章或页面销毁（invalidate）使旧续体作废，防止旧加载覆盖新章状态
export class ReaderLoadGuard {
  private gen: number = 0;

  begin(): number {
    this.gen += 1;
    return this.gen;
  }

  isStale(gen: number): boolean {
    return gen !== this.gen;
  }

  invalidate(): void {
    this.gen += 1;
  }
}
