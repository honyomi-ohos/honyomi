// 路径形变动画核心：解析 M/L/C/Z 绝对坐标 SVG 路径，对两组同构命令逐数值线性插值。
// 数据取自 Mihon anim_updates_enter / anim_library_enter / anim_browse_enter.xml 的
// pathType valueFrom/valueTo（Android 要求两端命令结构一致，此处同理）。
// 渲染端为 ArkUI 绘制组件 Path（commands 单位 px），调用方传入 坐标单位->px 缩放。
// 填充遵循环绕规则：外轮廓逆时针、洞顺时针（与 Android VectorDrawable nonZero 一致）。

export class PathSeg {
  cmd: string = 'M';
  nums: number[] = [];
}

const PATH_TOKEN_RE: RegExp = new RegExp('[MLCZmlcz]|-?[0-9]*\\.?[0-9]+', 'g');

export class PathMorph {
  private fromSegs: PathSeg[] = [];
  private toSegs: PathSeg[] = [];
  private fromRaw: string;
  private toRaw: string;
  private valid: boolean = false;

  constructor(from: string, to: string) {
    this.fromRaw = from;
    this.toRaw = to;
    this.fromSegs = PathMorph.parse(from);
    this.toSegs = PathMorph.parse(to);
    this.valid = PathMorph.compatible(this.fromSegs, this.toSegs);
  }

  static parse(d: string): PathSeg[] {
    const matched: RegExpMatchArray | null = d.match(PATH_TOKEN_RE);
    const tokens: string[] = matched ?? [];
    const segs: PathSeg[] = [];
    let cur: PathSeg | undefined = undefined;
    for (let i = 0; i < tokens.length; i++) {
      const tk: string = tokens[i];
      const c: string = tk.charAt(0);
      if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
        const seg: PathSeg = new PathSeg();
        seg.cmd = c.toUpperCase();
        segs.push(seg);
        cur = seg;
      } else if (cur !== undefined) {
        cur.nums.push(Number(tk));
      }
    }
    return segs;
  }

  static compatible(a: PathSeg[], b: PathSeg[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i].cmd !== b[i].cmd || a[i].nums.length !== b[i].nums.length) {
        return false;
      }
    }
    return true;
  }

  static fmt(v: number): string {
    return (Math.round(v * 100) / 100).toString();
  }

  // t ∈ [0,1]：0=未选中形，1=选中形；scale 为路径坐标到 px 的缩放
  valueAt(t: number, scale: number): string {
    if (!this.valid) {
      return t < 0.5 ? this.fromRaw : this.toRaw;
    }
    const tc: number = Math.min(1, Math.max(0, t));
    const parts: string[] = [];
    for (let i = 0; i < this.fromSegs.length; i++) {
      const f: PathSeg = this.fromSegs[i];
      const o: PathSeg = this.toSegs[i];
      parts.push(f.cmd);
      for (let j = 0; j < f.nums.length; j++) {
        const v: number = (f.nums[j] + (o.nums[j] - f.nums[j]) * tc) * scale;
        parts.push(PathMorph.fmt(v));
      }
    }
    return parts.join(' ');
  }
}

// ---------------- Mihon AVD pathData 数据 ----------------

// updates：星形描边+实心感叹号 -> 实心星形+感叹号挖空（AVD 原文，24 视口）
const UPDATES_FROM: string =
  'M 23 12 L 20.56 9.22 L 20.9 5.54 L 17.29 4.72 L 15.4 1.54 L 12 3 L 8.6 1.54 L 6.71 4.72 L 3.1 5.53 L 3.44 9.21 L 1 12 L 3.44 14.78 L 3.1 18.47 L 6.71 19.29 L 8.6 22.47 L 12 21 L 15.4 22.46 L 17.29 19.28 L 20.9 18.46 L 20.56 14.78 L 23 12 Z ' +
    'M 9.42 19.93 L 7.99 17.52 L 5.25 16.9 L 5.51 14.1 L 3.66 12 L 5.51 9.88 L 5.25 7.1 L 7.99 6.49 L 9.42 4.08 L 12 5.18 L 14.58 4.07 L 16.01 6.48 L 18.75 7.1 L 18.49 9.89 L 20.34 12 L 18.49 14.11 L 18.49 14.11 L 18.75 16.9 L 16.01 17.52 L 14.58 19.93 L 12 18.82 L 9.42 19.93 ' +
    'M 11 15 L 13 15 L 13 15.5 L 13 16 L 13 17 L 11 17 L 11 15 ' +
    'M 11 7 L 13 7 L 13 13 L 11 13 L 11 7';

const UPDATES_TO: string =
  'M 23 12 L 20.56 9.22 L 20.9 5.54 L 17.29 4.72 L 15.4 1.54 L 12 3 L 8.6 1.54 L 6.71 4.72 L 3.1 5.53 L 3.44 9.21 L 1 12 L 3.44 14.78 L 3.1 18.47 L 6.71 19.29 L 8.6 22.47 L 12 21 L 15.4 22.46 L 17.29 19.28 L 20.9 18.46 L 20.56 14.78 L 23 12 Z ' +
    'M 12 13 L 11.5 13 L 11 13 L 11 12 L 11 11 L 11 10 L 11 9 L 11 8 L 11 7 L 12 7 L 13 7 L 13 7.857 L 13 8.714 L 13 9.571 L 13 10.429 L 13 11.286 L 13 12.143 L 13 13 L 13 13 L 13 13 L 12.5 13 L 12 13 ' +
    'M 11 15 L 13 15 L 13 16.058 L 13 17 L 13 17 L 11 17 L 11 15 ' +
    'M 12 10 L 12 10 L 12 10 L 12 10 L 12 10';

// library：书签描边 -> 实心书签（内层子路径保持反向绕行）（AVD 原文，1080 视口）
const LIBRARY_FROM: string =
  'M 634.454 90.84 C 543.069 90.84 451.685 90.84 360.3 90.84 C 310.84 90.84 270.38 131.3 270.38 180.76 C 270.38 360.61 270.38 540.46 270.38 720.31 C 270.38 769.76 310.84 810.23 360.3 810.23 C 540.147 810.23 719.993 810.23 899.84 810.23 C 949.3 810.23 989.77 769.76 989.77 720.31 C 989.77 540.46 989.77 360.61 989.77 180.76 C 989.77 131.3 949.3 90.84 899.84 90.84 C 811.378 90.84 722.916 90.84 634.454 90.84 ' +
    'M 899.84 720.31 C 834.876 720.31 769.913 720.31 704.949 720.31 C 590.066 720.31 475.183 720.31 360.3 720.31 C 360.3 540.46 360.3 360.61 360.3 180.76 C 435.237 180.76 510.173 180.76 585.11 180.76 L 585.11 180.76 C 585.11 315.647 585.11 450.533 585.11 585.42 C 630.073 551.7 675.037 517.98 720 484.26 C 764.96 517.98 809.92 551.7 854.88 585.42 C 854.88 450.533 854.88 315.647 854.88 180.76 C 869.867 180.76 884.853 180.76 899.84 180.76 C 899.84 360.61 899.84 540.46 899.84 720.31';

const LIBRARY_TO: string =
  'M 900 90 C 720 90 540 90 360 90 C 310.5 90 270 130.5 270 180 C 270 360 270 540 270 720 C 270 769.5 310.5 810 360 810 C 540 810 720 810 900 810 C 949.5 810 990 769.5 990 720 C 990 540 990 360 990 180 C 990 130.5 949.5 90 900 90 C 900 90 900 90 900 90 ' +
    'M 900 540 C 862.5 517.5 825 495 787.5 472.5 C 750 495 712.5 517.5 675 540 C 675 540 675 540 675 540 C 675 471.351 675 402.701 675 334.052 L 675 180 C 675 180 675 180 675 180 C 713.708 180 752.416 180 791.124 180 C 827.416 180 863.708 180 900 180 C 900 233.194 900 286.387 900 339.581 C 900 406.387 900 473.194 900 540 C 900 540 900 540 900 540';

// browse：弯曲指针 -> 圆盘（子路径2为顺时针圆点洞，选中态收拢为圆心退化点，
// 由独立的 dot 弹出层覆盖选中实心点，等效 AVD 中 clip-path 的效果；
// 子路径3由退化点长成反向指针四边形，作为圆盘内的洞）（24 视口）
const BROWSE_FROM: string =
  'M 9.99 9.99 C 9.408 11.242 8.827 12.493 8.245 13.745 C 7.663 14.997 7.082 16.248 6.5 17.5 C 6.5 17.5 6.5 17.5 6.5 17.5 C 9.003 16.337 11.507 15.173 14.01 14.01 C 15.173 11.507 16.337 9.003 17.5 6.5 C 14.997 7.663 12.493 8.827 9.99 9.99 ' +
    'M 12 10.9 C 12.61 10.9 13.1 11.39 13.1 12 C 13.1 12.61 12.61 13.1 12 13.1 C 11.39 13.1 10.9 12.61 10.9 12 C 10.9 11.39 11.39 10.9 12 10.9 ' +
    'M 12 12 L 12 12 L 12 12 L 12 12 L 12 12 L 12 12 L 12 12';

const BROWSE_TO: string =
  'M 12 2 C 6.48 2 2 6.48 2 12 C 2 17.141 5.886 21.38 10.878 21.938 C 11.247 21.979 11.621 22 12 22 C 17.52 22 22 17.52 22 12 C 22 6.48 17.52 2 12 2 C 12 2 12 2 12 2 ' +
    'M 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 C 12 12 12 12 12 12 ' +
    'M 14.19 14.19 L 6 18 L 6 18 L 9.81 9.81 L 18 6 L 14.19 14.19 L 14.19 14.19';

export const UPDATES_MORPH: PathMorph = new PathMorph(UPDATES_FROM, UPDATES_TO);

export const LIBRARY_MORPH: PathMorph = new PathMorph(LIBRARY_FROM, LIBRARY_TO);

export const BROWSE_MORPH: PathMorph = new PathMorph(BROWSE_FROM, BROWSE_TO);
