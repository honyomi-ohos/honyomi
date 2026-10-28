import { OcrTextBox, PageTransData } from '../../translate/MangaOcr';

// 漫画页译文叠加层：按 objectFit 数学对齐图片显示矩形，
// 逐框以采样底色覆盖原文并自适应字号排版译文；不响应任何触摸
@Component
export struct MangaTransOverlay {
  @Prop data: PageTransData = new PageTransData(1, 1, []);
  @Prop fit: ImageFit = ImageFit.Contain;
  @State viewW: number = 0;
  @State viewH: number = 0;

  build() {
    if (this.data.boxes.length > 0) {
      Stack() {
        ForEach(this.data.boxes, (box: OcrTextBox) => {
          Column() {
            Text(box.text)
              .fontSize(this.fontSizeVp(box))
              .fontColor(box.fg)
              .textAlign(TextAlign.Center)
              .maxLines(this.maxLinesOf(box))
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(this.fontSizeVp(box) * 1.22)
          }
          .width(this.boxWVp(box))
          .height(this.boxHVp(box))
          .backgroundColor(box.bg)
          .borderRadius(Math.min(this.boxHVp(box) / 4, 8))
          .position({ x: this.boxXVp(box), y: this.boxYVp(box) })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding(2)
          .clip(true)
        }, (box: OcrTextBox) => `${box.x}|${box.y}|${box.w}|${box.h}|${box.text}`)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onAreaChange((_old: Area, newArea: Area) => {
        const w: number = Number(newArea.width);
        const h: number = Number(newArea.height);
        if (w > 0 && h > 0) {
          this.viewW = w;
          this.viewH = h;
        }
      })
    }
  }

  // objectFit 数学：图片在容器内的显示比例（Contain 居中留白 / Cover 居中裁切）
  private dispScale(): number {
    const iw: number = this.data.imgW;
    const ih: number = this.data.imgH;
    if (iw <= 0 || ih <= 0 || this.viewW <= 0 || this.viewH <= 0) {
      return 0;
    }
    const sx: number = this.viewW / iw;
    const sy: number = this.viewH / ih;
    return this.fit === ImageFit.Cover ? Math.max(sx, sy) : Math.min(sx, sy);
  }

  private dispOffX(): number {
    return (this.viewW - this.data.imgW * this.dispScale()) / 2;
  }

  private dispOffY(): number {
    return (this.viewH - this.data.imgH * this.dispScale()) / 2;
  }

  private boxXVp(box: OcrTextBox): number {
    return this.dispOffX() + box.x * this.dispScale();
  }

  private boxYVp(box: OcrTextBox): number {
    return this.dispOffY() + box.y * this.dispScale();
  }

  private boxWVp(box: OcrTextBox): number {
    return box.w * this.dispScale();
  }

  private boxHVp(box: OcrTextBox): number {
    return box.h * this.dispScale();
  }

  // 自适应字号：文字面积 ≈ 字数×0.98×字号²（CJK 近方形、混排取折中），行高系数 1.22；
  // 上限不超过框高 90% 与框宽，下限 7vp
  private fontSizeVp(box: OcrTextBox): number {
    const w: number = this.boxWVp(box);
    const h: number = this.boxHVp(box);
    const n: number = box.text.length;
    if (w <= 0 || h <= 0 || n === 0) {
      return 12;
    }
    const fs: number = Math.sqrt(w * h / (n * 0.98));
    return Math.max(7, Math.min(34, h * 0.9, w, fs));
  }

  private maxLinesOf(box: OcrTextBox): number {
    const h: number = this.boxHVp(box);
    const fs: number = this.fontSizeVp(box);
    if (fs <= 0 || h <= 0) {
      return 4;
    }
    return Math.max(1, Math.min(10, Math.floor(h / (fs * 1.22))));
  }
}
