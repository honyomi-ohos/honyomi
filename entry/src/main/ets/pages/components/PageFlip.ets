/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { common2D, drawing } from '@kit.ArkGraphics2D';
import { NodeController, FrameNode, RenderNode, DrawContext, UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

// 仿真翻页（移植官方 PageFlip 示例的截图 + RenderNode 绘制）。
// 手势与点击驱动当前页/上一页截图，沿右缘（或镜像后的左缘）卷曲；状态放在实例上，可多处复用。
const FLIP_DISTANCE_FRACTION: number = 20;
const FLIP_X_DIFF: number = -100;
const FLIP_TICK_MS: number = 16;
const FLIP_SIXTY: number = 0.6;

enum FlipDrawPos {
  NONE = 1,
  TOP = 2,
  BOTTOM = 3,
  MIDDLE = 4
}

enum FlipDrawState {
  NONE = 1,
  MOVING = 2,
  RELEASE = 3
}

enum FlipMove {
  NONE = 0,
  PREV = 1,
  NEXT = 2
}

class FlipPoint {
  x: number = 0;
  y: number = 0;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

class FlipModel {
  viewWidth: number = 0;
  viewHeight: number = 0;
  positionX: number = -1;
  positionY: number = -1;
  drawPosition: number = FlipDrawPos.NONE;
  drawState: number = FlipDrawState.NONE;
  pixelMap: image.PixelMap | undefined = undefined;
  isFinished: boolean = false;
  flipPositionY: number = 0;
  fromLeft: boolean = false;

  private pathABrush: drawing.Brush = new drawing.Brush();
  private pathCBrush: drawing.Brush = new drawing.Brush();
  private pathA: drawing.Path = new drawing.Path();
  private pathC: drawing.Path = new drawing.Path();
  private pointA: FlipPoint = new FlipPoint(-1, -1);
  private pointB: FlipPoint = new FlipPoint(0, 0);
  private pointC: FlipPoint = new FlipPoint(0, 0);
  private pointD: FlipPoint = new FlipPoint(0, 0);
  private pointE: FlipPoint = new FlipPoint(0, 0);
  private pointF: FlipPoint = new FlipPoint(0, 0);
  private pointG: FlipPoint = new FlipPoint(0, 0);
  private pointH: FlipPoint = new FlipPoint(0, 0);
  private pointI: FlipPoint = new FlipPoint(0, 0);
  private pointJ: FlipPoint = new FlipPoint(0, 0);
  private pointK: FlipPoint = new FlipPoint(0, 0);
  private lPathAShadowDis: number = 0;
  private rPathAShadowDis: number = 0;
  private ready: boolean = false;

  releaseMap(): void {
    if (this.pixelMap !== undefined) {
      this.pixelMap.release();
      this.pixelMap = undefined;
    }
  }

  paint(canvas: drawing.Canvas): void {
    if (!canIUse('SystemCapability.Graphics.Drawing')) {
      return;
    }
    if (this.positionX < 0 || this.positionY < 0 || this.pixelMap === undefined) {
      return;
    }
    if (this.viewWidth <= 1 || this.viewHeight <= 1) {
      return;
    }
    this.ensureBrushes();
    if (this.fromLeft) {
      canvas.save();
      const mirror = new drawing.Matrix();
      const mv: number[] = [-1, 0, this.viewWidth, 0, 1, 0, 0, 0, 1];
      mirror.setMatrix(mv);
      canvas.concatMatrix(mirror);
    }
    this.initGeometry();
    if (this.ready) {
      this.drawPathBShadow(canvas);
      this.drawPathC(canvas);
      this.buildPathA();
      this.drawPathAContent(canvas);
    }
    if (this.fromLeft) {
      canvas.restore();
    }
  }

  private ensureBrushes(): void {
    const paper: common2D.Color = { alpha: 255, red: 255, green: 235, blue: 195 };
    const back: common2D.Color = { alpha: 120, red: 186, green: 172, blue: 145 };
    this.pathABrush.setColor(paper);
    this.pathCBrush.setColor(back);
  }

  private initGeometry(): void {
    this.ready = false;
    const x = this.positionX;
    const y = this.positionY;
    const viewWidth = this.viewWidth;
    const viewHeight = this.viewHeight;
    this.pointA = new FlipPoint(x, y);
    if (x === -1 && y === -1) {
      return;
    }
    const touch = new FlipPoint(x, y);
    if (FlipDrawPos.TOP === this.drawPosition) {
      this.pointF = new FlipPoint(viewWidth, 0);
      if (this.drawState !== FlipDrawState.RELEASE) {
        this.calcPointAByTouch(touch);
      }
    } else if (FlipDrawPos.BOTTOM === this.drawPosition) {
      this.pointF = new FlipPoint(viewWidth, viewHeight);
      if (this.drawState !== FlipDrawState.RELEASE) {
        this.calcPointAByTouch(touch);
      }
    } else {
      this.pointA.y = viewHeight - 1;
      this.pointF = new FlipPoint(viewWidth, viewHeight);
    }
    this.flipPositionY = this.pointA.y;
    this.calcPoints();
  }

  private calcPointAByTouch(touch: FlipPoint): void {
    const viewWidth = this.viewWidth;
    const viewHeight = this.viewHeight;
    const r = FLIP_SIXTY * viewWidth;
    this.pointA.x = touch.x;
    const dx = touch.x - (viewWidth - r);
    const inside = r * r - dx * dx;
    if (inside <= 0) {
      this.pointA.y = touch.y;
      return;
    }
    const span = Math.sqrt(inside);
    if (this.pointF.y === viewHeight) {
      const tmpY = viewHeight - span;
      this.pointA.y = touch.y >= tmpY ? touch.y : tmpY;
    } else {
      this.pointA.y = touch.y >= span ? span : touch.y;
    }
  }

  private calcPoints(): void {
    const a = this.pointA;
    const f = this.pointF;
    if (Math.abs(f.x - a.x) < 0.5 && Math.abs(f.y - a.y) < 0.5) {
      return;
    }
    this.pointG.x = (a.x + f.x) / 2;
    this.pointG.y = (a.y + f.y) / 2;
    const g = this.pointG;
    const denomX = f.x - g.x;
    const denomY = f.y - g.y;
    if (Math.abs(denomX) < 0.01 || Math.abs(denomY) < 0.01) {
      return;
    }
    this.pointE.x = g.x - (f.y - g.y) * (f.y - g.y) / denomX;
    this.pointE.y = f.y;
    this.pointH.x = f.x;
    this.pointH.y = g.y - (f.x - g.x) * (f.x - g.x) / denomY;
    this.pointC.x = this.pointE.x - (f.x - this.pointE.x) / 2;
    this.pointC.y = f.y;
    this.pointJ.x = f.x;
    this.pointJ.y = this.pointH.y - (f.y - this.pointH.y) / 2;
    this.pointB = this.intersect(a, this.pointE, this.pointC, this.pointJ);
    this.pointK = this.intersect(a, this.pointH, this.pointC, this.pointJ);
    this.pointD.x = (this.pointC.x + 2 * this.pointE.x + this.pointB.x) / 4;
    this.pointD.y = (2 * this.pointE.y + this.pointC.y + this.pointB.y) / 4;
    this.pointI.x = (this.pointJ.x + 2 * this.pointH.x + this.pointK.x) / 4;
    this.pointI.y = (2 * this.pointH.y + this.pointJ.y + this.pointK.y) / 4;
    const lA = a.y - this.pointE.y;
    const lB = this.pointE.x - a.x;
    const lC = a.x * this.pointE.y - this.pointE.x * a.y;
    this.lPathAShadowDis = Math.abs((lA * this.pointD.x + lB * this.pointD.y + lC) / Math.hypot(lA, lB));
    const rA = a.y - this.pointH.y;
    const rB = this.pointH.x - a.x;
    const rC = a.x * this.pointH.y - this.pointH.x * a.y;
    this.rPathAShadowDis = Math.abs((rA * this.pointI.x + rB * this.pointI.y + rC) / Math.hypot(rA, rB));
    if (!this.areaInWindow()) {
      this.isFinished = true;
    }
    if (!this.pointsFinite()) {
      return;
    }
    this.ready = true;
  }

  private pointsFinite(): boolean {
    const pts: FlipPoint[] = [this.pointA, this.pointB, this.pointC, this.pointD, this.pointE,
      this.pointF, this.pointH, this.pointI, this.pointJ, this.pointK];
    for (let i = 0; i < pts.length; i++) {
      if (!Number.isFinite(pts[i].x) || !Number.isFinite(pts[i].y)) {
        return false;
      }
    }
    return true;
  }

  private areaInWindow(): boolean {
    const viewHeight = this.viewHeight;
    const dx = this.pointD.x - this.pointI.x;
    if (Math.abs(dx) < 0.01) {
      return true;
    }
    const k = (this.pointD.y - this.pointI.y) / dx;
    const b = this.pointD.y - k * this.pointD.x;
    if ((this.pointF.y === 0 && b > viewHeight) || (this.pointF.y !== 0 && b < 0)) {
      return false;
    }
    return true;
  }

  private intersect(p1: FlipPoint, p2: FlipPoint, p3: FlipPoint, p4: FlipPoint): FlipPoint {
    const x1 = p1.x;
    const y1 = p1.y;
    const x2 = p2.x;
    const y2 = p2.y;
    const x3 = p3.x;
    const y3 = p3.y;
    const x4 = p4.x;
    const y4 = p4.y;
    const denom = (x3 - x4) * (y1 - y2) - (x1 - x2) * (y3 - y4);
    if (Math.abs(denom) < 0.01) {
      return new FlipPoint(p1.x, p1.y);
    }
    const px = ((x1 - x2) * (x3 * y4 - x4 * y3) - (x3 - x4) * (x1 * y2 - x2 * y1)) / denom;
    const py = ((y1 - y2) * (x3 * y4 - x4 * y3) - (x1 * y2 - x2 * y1) * (y3 - y4)) /
      ((y1 - y2) * (x3 - x4) - (x1 - x2) * (y3 - y4));
    return new FlipPoint(px, py);
  }

  private buildPathA(): void {
    const viewWidth = this.viewWidth;
    const viewHeight = this.viewHeight;
    if (this.pointF.x === viewWidth && this.pointF.y === 0) {
      this.pathA.reset();
      this.pathA.lineTo(this.pointC.x, this.pointC.y);
      this.pathA.quadTo(this.pointE.x, this.pointE.y, this.pointB.x, this.pointB.y);
      this.pathA.lineTo(this.pointA.x, this.pointA.y);
      this.pathA.lineTo(this.pointK.x, this.pointK.y);
      this.pathA.quadTo(this.pointH.x, this.pointH.y, this.pointJ.x, this.pointJ.y);
      this.pathA.lineTo(viewWidth, viewHeight);
      this.pathA.lineTo(0, viewHeight);
      this.pathA.close();
    }
    if (this.pointF.x === viewWidth && this.pointF.y === viewHeight) {
      this.pathA.reset();
      this.pathA.lineTo(0, viewHeight);
      this.pathA.lineTo(this.pointC.x, this.pointC.y);
      this.pathA.quadTo(this.pointE.x, this.pointE.y, this.pointB.x, this.pointB.y);
      this.pathA.lineTo(this.pointA.x, this.pointA.y);
      this.pathA.lineTo(this.pointK.x, this.pointK.y);
      this.pathA.quadTo(this.pointH.x, this.pointH.y, this.pointJ.x, this.pointJ.y);
      this.pathA.lineTo(viewWidth, 0);
      this.pathA.close();
    }
  }

  private meshVerts(): number[] {
    const w = this.viewWidth;
    const h = this.viewHeight;
    if (this.fromLeft) {
      return [w, 0, 0, 0, w, h, 0, h];
    }
    return [0, 0, w, 0, 0, h, w, h];
  }

  private drawPathC(canvas: drawing.Canvas): void {
    const page = this.pixelMap;
    if (page === undefined) {
      return;
    }
    canvas.attachBrush(this.pathABrush);
    this.pathC.reset();
    this.pathC.moveTo(this.pointI.x, this.pointI.y);
    this.pathC.lineTo(this.pointD.x, this.pointD.y);
    this.pathC.lineTo(this.pointB.x, this.pointB.y);
    this.pathC.lineTo(this.pointA.x, this.pointA.y);
    this.pathC.lineTo(this.pointK.x, this.pointK.y);
    this.pathC.close();
    canvas.drawPath(this.pathC);
    canvas.save();
    canvas.clipPath(this.pathC);
    const eh = Math.hypot(this.pointF.x - this.pointE.x, this.pointH.y - this.pointF.y);
    if (eh > 0.01) {
      const sin0 = (this.pointF.x - this.pointE.x) / eh;
      const cos0 = (this.pointH.y - this.pointF.y) / eh;
      const value: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 1];
      value[0] = -(1 - 2 * sin0 * sin0);
      value[1] = 2 * sin0 * cos0;
      value[3] = 2 * sin0 * cos0;
      value[4] = 1 - 2 * sin0 * sin0;
      const matrix = new drawing.Matrix();
      matrix.setMatrix(value);
      matrix.preTranslate(-this.pointE.x, -this.pointE.y);
      matrix.postTranslate(this.pointE.x, this.pointE.y);
      canvas.concatMatrix(matrix);
    }
    const colors: number[] | null = null;
    canvas.drawPixelMapMesh(page, 1, 1, this.meshVerts(), 0, colors, 0);
    canvas.restore();
    canvas.detachBrush();
    canvas.attachBrush(this.pathCBrush);
    canvas.drawPath(this.pathC);
    canvas.detachBrush();
    canvas.save();
    canvas.clipPath(this.pathC);
    // drawShadow 内部 restore，与这里的 save 配对
    this.drawPathCShadow(canvas);
  }

  private drawPathAContent(canvas: drawing.Canvas): void {
    const page = this.pixelMap;
    if (page === undefined) {
      return;
    }
    canvas.attachBrush(this.pathABrush);
    canvas.save();
    canvas.clipPath(this.pathA);
    const colors: number[] | null = null;
    canvas.drawPixelMapMesh(page, 1, 1, this.meshVerts(), 0, colors, 0);
    canvas.restore();
    if (this.drawPosition === FlipDrawPos.MIDDLE) {
      this.drawHorizontalShadow(canvas);
    } else {
      this.drawLeftShadow(canvas);
      this.drawRightShadow(canvas);
    }
    canvas.detachBrush();
  }

  private drawPathBShadow(canvas: drawing.Canvas): void {
    canvas.save();
    const deepColor: number = 0xff111111;
    const lightColor: number = 0x00111111;
    const gradientColors: number[] = [deepColor, lightColor];
    const viewWidth = this.viewWidth;
    const viewHeight = this.viewHeight;
    const aToF = Math.hypot(this.pointA.x - this.pointF.x, this.pointA.y - this.pointF.y);
    const diagonal = Math.hypot(viewWidth, viewHeight);
    let left = 0;
    let right = 0;
    const top = this.pointC.y;
    const bottom = diagonal + this.pointC.y;
    if (this.pointF.y === 0) {
      left = this.pointC.x;
      right = this.pointC.x + aToF / 4;
    } else {
      left = this.pointC.x - aToF / 4;
      right = this.pointC.x;
    }
    const radians = Math.atan2(this.pointE.x - this.pointF.x, this.pointH.y - this.pointF.y);
    const rotateDegrees = radians * 180 / Math.PI;
    const startPt: common2D.Point = { x: this.pointF.y === 0 ? right : left, y: top };
    const endPt: common2D.Point = { x: this.pointF.y === 0 ? left : right, y: top };
    const shader = drawing.ShaderEffect.createLinearGradient(endPt, startPt, gradientColors, drawing.TileMode.MIRROR);
    canvas.rotate(rotateDegrees, this.pointC.x, this.pointC.y);
    const rect: common2D.Rect = { left: left, top: top, right: right, bottom: bottom };
    this.drawShadow(canvas, shader, rect);
  }

  private drawPathCShadow(canvas: drawing.Canvas): void {
    const deepColor: number = 0x88111111;
    const lightColor: number = 0x00111111;
    const gradientColors: number[] = [lightColor, deepColor];
    const viewWidth = this.viewWidth;
    const viewHeight = this.viewHeight;
    const diagonal = Math.hypot(viewWidth, viewHeight);
    const midCE = (this.pointC.x + this.pointE.x) / 2;
    const midJH = (this.pointJ.y + this.pointH.y) / 2;
    const minDis = Math.min(Math.abs(midCE - this.pointE.x), Math.abs(midJH - this.pointH.y));
    let left = 0;
    let right = 0;
    const top = this.pointC.y;
    const bottom = diagonal + this.pointC.y;
    if (this.pointF.y === 0) {
      left = this.pointC.x - 1;
      right = this.pointC.x + minDis;
    } else {
      left = this.pointC.x - minDis;
      right = this.pointC.x + 1;
    }
    const radians = Math.atan2(this.pointE.x - this.pointF.x, this.pointH.y - this.pointF.y);
    const rotateDegrees = radians * 180 / Math.PI;
    const startPt: common2D.Point = { x: this.pointF.y === 0 ? right : left, y: top };
    const endPt: common2D.Point = { x: this.pointF.y === 0 ? left : right, y: top };
    const shader = drawing.ShaderEffect.createLinearGradient(endPt, startPt, gradientColors, drawing.TileMode.MIRROR);
    canvas.rotate(rotateDegrees, this.pointC.x, this.pointC.y);
    const rect: common2D.Rect = { left: left, top: top, right: right, bottom: bottom };
    this.drawShadow(canvas, shader, rect);
  }

  private drawLeftShadow(canvas: drawing.Canvas): void {
    canvas.save();
    const deepColor: number = 0x88111111;
    const lightColor: number = 0x00111111;
    const gradientColors: number[] = [lightColor, deepColor];
    let left = 0;
    let right = 0;
    const top = this.pointE.y;
    const bottom = this.pointE.y + this.viewHeight;
    if (this.pointF.y === 0) {
      left = this.pointE.x - this.lPathAShadowDis / 2;
      right = this.pointE.x;
    } else {
      left = this.pointE.x;
      right = this.pointE.x + this.lPathAShadowDis / 2;
    }
    const radians = Math.atan2(this.pointE.x - this.pointA.x, this.pointA.y - this.pointE.y);
    const rotateDegrees = radians * 180 / Math.PI;
    const startPt: common2D.Point = { x: this.pointF.y === this.viewHeight ? left : right, y: top };
    const endPt: common2D.Point = { x: this.pointF.y === this.viewHeight ? right : left, y: top };
    const shader = drawing.ShaderEffect.createLinearGradient(endPt, startPt, gradientColors, drawing.TileMode.MIRROR);
    const tmp = new drawing.Path();
    const inset = Math.max(this.rPathAShadowDis, this.lPathAShadowDis) / 2;
    tmp.moveTo(this.pointA.x - inset, this.pointA.y);
    tmp.lineTo(this.pointD.x, this.pointD.y);
    tmp.lineTo(this.pointE.x, this.pointE.y);
    tmp.lineTo(this.pointA.x, this.pointA.y);
    tmp.close();
    canvas.clipPath(this.pathA);
    canvas.clipPath(tmp, drawing.ClipOp.INTERSECT);
    canvas.rotate(rotateDegrees, this.pointE.x, this.pointE.y);
    const rect: common2D.Rect = { left: left, top: top, right: right, bottom: bottom };
    this.drawShadow(canvas, shader, rect);
  }

  private drawRightShadow(canvas: drawing.Canvas): void {
    canvas.save();
    canvas.clipPath(this.pathA);
    const deepColor: number = 0x88111111;
    const lightColor: number = 0x00111111;
    const gradientColors: number[] = [deepColor, lightColor, lightColor, lightColor];
    const diagonal = Math.hypot(this.viewWidth, this.viewHeight);
    const left = this.pointH.x;
    const right = this.pointH.x + diagonal * 10;
    let top = 0;
    let bottom = 0;
    if (this.pointF.y === 0) {
      top = this.pointH.y - this.rPathAShadowDis / 2;
      bottom = this.pointH.y;
    } else {
      top = this.pointH.y;
      bottom = this.pointH.y + this.rPathAShadowDis / 2;
    }
    const radians = Math.atan2(this.pointA.y - this.pointH.y, this.pointA.x - this.pointH.x);
    const rotateDegrees = radians * 180 / Math.PI;
    const startPt: common2D.Point = { x: left, y: this.pointF.y === this.viewHeight ? bottom : top };
    const endPt: common2D.Point = { x: left, y: this.pointF.y === this.viewHeight ? top : bottom };
    const shader = drawing.ShaderEffect.createLinearGradient(endPt, startPt, gradientColors, drawing.TileMode.MIRROR);
    const tmp = new drawing.Path();
    const inset = Math.max(this.rPathAShadowDis, this.lPathAShadowDis) / 2;
    tmp.moveTo(this.pointA.x - inset, this.pointA.y);
    tmp.lineTo(this.pointH.x, this.pointH.y);
    tmp.lineTo(this.pointA.x, this.pointA.y);
    tmp.close();
    canvas.clipPath(this.pathA);
    canvas.clipPath(tmp, drawing.ClipOp.INTERSECT);
    canvas.rotate(rotateDegrees, this.pointH.x, this.pointH.y);
    const rect: common2D.Rect = { left: left, top: top, right: right, bottom: bottom };
    this.drawShadow(canvas, shader, rect);
  }

  private drawHorizontalShadow(canvas: drawing.Canvas): void {
    canvas.save();
    const deepColor: number = 0x88111111;
    const lightColor: number = 0x00111111;
    const gradientColors: number[] = [lightColor, deepColor];
    const left = this.pointA.x - Math.min(30, this.rPathAShadowDis / 2);
    const right = this.pointA.x + 70;
    const top = 0;
    const bottom = this.viewHeight;
    canvas.clipPath(this.pathA);
    const startPt: common2D.Point = { x: right, y: top };
    const endPt: common2D.Point = { x: left, y: top };
    const shader = drawing.ShaderEffect.createLinearGradient(endPt, startPt, gradientColors, drawing.TileMode.MIRROR);
    const rect: common2D.Rect = { left: left, top: top, right: right, bottom: bottom };
    this.drawShadow(canvas, shader, rect);
  }

  private drawShadow(canvas: drawing.Canvas, shader: drawing.ShaderEffect, rect: common2D.Rect): void {
    const brush = new drawing.Brush();
    brush.setShaderEffect(shader);
    canvas.attachBrush(brush);
    canvas.drawRect(rect.left, rect.top, rect.right, rect.bottom);
    canvas.detachBrush();
    canvas.restore();
  }
}

class FlipRenderNode extends RenderNode {
  model: FlipModel;

  constructor(model: FlipModel) {
    super();
    this.model = model;
  }

  draw(context: DrawContext): void {
    this.model.paint(context.canvas);
  }
}

class FlipNodeController extends NodeController {
  private root: FrameNode | null = null;
  private model: FlipModel | null = null;
  private viewWvp: number = 0;
  private viewHvp: number = 0;

  setModel(model: FlipModel): void {
    this.model = model;
  }

  setSize(wvp: number, hvp: number): void {
    this.viewWvp = wvp;
    this.viewHvp = hvp;
    this.applyFrame();
  }

  makeNode(uiContext: UIContext): FrameNode | null {
    this.root = new FrameNode(uiContext);
    this.applyFrame();
    return this.root;
  }

  redraw(): void {
    if (this.root === null || this.model === null || this.viewWvp <= 0 || this.viewHvp <= 0) {
      return;
    }
    const render = this.root.getRenderNode();
    if (render === null) {
      return;
    }
    render.clearChildren();
    const node = new FlipRenderNode(this.model);
    node.frame = { x: 0, y: 0, width: this.viewWvp, height: this.viewHvp };
    render.appendChild(node);
  }

  clear(): void {
    if (this.root === null) {
      return;
    }
    const render = this.root.getRenderNode();
    if (render !== null) {
      render.clearChildren();
    }
  }

  private applyFrame(): void {
    if (this.root === null) {
      return;
    }
    const render = this.root.getRenderNode();
    if (render !== null) {
      render.frame = { x: 0, y: 0, width: this.viewWvp, height: this.viewHvp };
    }
  }
}

let flipSerial: number = 0;

@Builder
function emptyFlipPage(_index: number) {
  Column()
}

@Component
export struct EmulationFlipView {
  @Prop @Watch('syncIndex') index: number = 0;
  @Prop pageCount: number = 0;
  // 卷曲锚点在左缘（从右到左阅读）。算法仍按右缘计算，绘制时水平镜像。
  @Prop @Watch('syncFromLeft') fromLeft: boolean = false;
  // 点击“下一页”是否在左侧。与卷曲方向独立，便于漫画导航模式覆盖。
  @Prop nextOnLeft: boolean = false;
  // horizontal | vertical | edge | none
  @Prop tapMode: string = 'horizontal';
  @Prop flipEnabled: boolean = true;
  @Prop bgColor: ResourceColor = Color.Black;
  onIndexChange: (index: number) => void = (_index: number): void => {
  };
  onCenterTap: () => void = (): void => {
  };
  onOverscroll: (dir: number) => void = (_dir: number): void => {
  };
  @BuilderParam pageContent: (index: number) => void = emptyFlipPage;

  @State page: number = 0;
  @State hideCurrent: boolean = false;
  @State showCurl: boolean = false;
  @State areaW: number = 0;
  @State areaH: number = 0;
  private model: FlipModel = new FlipModel();
  private controller: FlipNodeController = new FlipNodeController();
  private pxW: number = 0;
  private pxH: number = 0;
  private panX: number = 0;
  private panReady: boolean = false;
  private drawing: boolean = false;
  private allowPan: boolean = true;
  private timeID: number = -1;
  private pageMove: number = FlipMove.NONE;
  private gestureMove: number = FlipMove.NONE;
  private drawPos: number = FlipDrawPos.NONE;
  private midId: string = '';
  private prevId: string = '';
  private nextId: string = '';
  private acceptExternal: boolean = true;

  aboutToAppear(): void {
    flipSerial += 1;
    this.midId = `pfMid${flipSerial}`;
    this.prevId = `pfPrev${flipSerial}`;
    this.nextId = `pfNext${flipSerial}`;
    this.page = this.index;
    this.model.fromLeft = this.fromLeft;
    this.controller.setModel(this.model);
  }

  aboutToDisappear(): void {
    this.cancelAnim();
    this.model.releaseMap();
    this.controller.clear();
  }

  private syncIndex(): void {
    if (!this.acceptExternal || this.index === this.page) {
      return;
    }
    this.cancelAnim();
    this.page = this.index;
  }

  private syncFromLeft(): void {
    this.model.fromLeft = this.fromLeft;
  }

  private cancelAnim(): void {
    if (this.timeID !== -1) {
      clearInterval(this.timeID);
      this.timeID = -1;
    }
    this.resetVisual();
  }

  private resetVisual(): void {
    this.model.positionX = -1;
    this.model.positionY = -1;
    this.model.drawPosition = FlipDrawPos.NONE;
    this.model.drawState = FlipDrawState.NONE;
    this.model.isFinished = false;
    this.hideCurrent = false;
    this.showCurl = false;
    this.gestureMove = FlipMove.NONE;
    this.pageMove = FlipMove.NONE;
    this.panX = 0;
    this.panReady = false;
    this.drawPos = FlipDrawPos.NONE;
    this.drawing = false;
    this.allowPan = true;
    this.controller.clear();
    this.model.releaseMap();
  }

  private algoX(localXVp: number): number {
    const px = this.getUIContext().vp2px(localXVp);
    if (this.fromLeft) {
      return this.pxW - px;
    }
    return px;
  }

  private canTurn(dir: number): boolean {
    if (this.pageCount <= 0) {
      return false;
    }
    if (dir > 0) {
      return this.page < this.pageCount - 1;
    }
    return this.page > 0;
  }

  private capture(id: string): boolean {
    this.model.releaseMap();
    try {
      this.model.pixelMap = this.getUIContext().getComponentSnapshot().getSync(id);
    } catch (_error) {
      this.model.pixelMap = undefined;
      return false;
    }
    return this.model.pixelMap !== undefined;
  }

  private redraw(): void {
    this.model.fromLeft = this.fromLeft;
    this.model.viewWidth = this.pxW;
    this.model.viewHeight = this.pxH;
    this.controller.setSize(this.areaW, this.areaH);
    this.controller.redraw();
  }

  private finishGesture(commit: boolean): void {
    if (this.timeID !== -1) {
      clearInterval(this.timeID);
      this.timeID = -1;
    }
    let next = this.page;
    let changed = false;
    if (commit) {
      if (this.pageMove === FlipMove.PREV && this.gestureMove === FlipMove.PREV) {
        next = this.page - 1;
        changed = true;
      }
      if (this.pageMove === FlipMove.NEXT && this.gestureMove === FlipMove.NEXT) {
        next = this.page + 1;
        changed = true;
      }
    }
    this.resetVisual();
    if (!changed) {
      return;
    }
    if (next < 0 || next >= this.pageCount) {
      return;
    }
    this.acceptExternal = false;
    this.page = next;
    this.onIndexChange(next);
    this.acceptExternal = true;
  }

  private armAuto(xDiff: number, yDiff: number): void {
    this.model.drawState = FlipDrawState.RELEASE;
    this.model.positionY = this.model.flipPositionY;
    if (this.gestureMove === FlipMove.PREV) {
      this.timeID = setInterval((): void => {
        const x = this.model.positionX + xDiff;
        const y = this.model.positionY + yDiff;
        if (x >= this.pxW - 1 || y >= this.pxH || y <= 0) {
          this.finishGesture(true);
        } else {
          this.model.positionX = x;
          this.model.positionY = y;
          this.redraw();
        }
      }, FLIP_TICK_MS);
    } else {
      this.model.isFinished = false;
      this.timeID = setInterval((): void => {
        if (this.model.isFinished) {
          this.finishGesture(true);
          return;
        }
        this.model.positionX = this.model.positionX + xDiff;
        this.redraw();
      }, FLIP_TICK_MS);
    }
  }

  private beginCurl(move: number, xPx: number, yPx: number, snapId: string): boolean {
    this.drawPos = FlipDrawPos.MIDDLE;
    this.pageMove = move;
    this.gestureMove = move;
    this.model.drawPosition = FlipDrawPos.MIDDLE;
    this.model.drawState = FlipDrawState.RELEASE;
    this.model.positionX = xPx;
    this.model.positionY = yPx;
    this.model.flipPositionY = this.pxH - 1;
    this.model.isFinished = false;
    if (!this.capture(snapId)) {
      this.resetVisual();
      return false;
    }
    if (move === FlipMove.NEXT) {
      this.hideCurrent = true;
    }
    this.showCurl = true;
    this.redraw();
    return true;
  }

  private onFinger(localX: number, localY: number): void {
    if (!this.flipEnabled || !this.allowPan || this.pxW <= 1 || this.timeID !== -1) {
      if (this.timeID !== -1) {
        this.finishGesture(true);
      }
      return;
    }
    const xVp = localX;
    if (!this.panReady) {
      this.panReady = true;
      this.panX = xVp;
      const yPx = this.getUIContext().vp2px(localY);
      if (yPx < this.pxH / 3) {
        this.drawPos = FlipDrawPos.TOP;
      } else if (yPx > this.pxH * 2 / 3) {
        this.drawPos = FlipDrawPos.BOTTOM;
      } else {
        this.drawPos = FlipDrawPos.MIDDLE;
      }
      this.model.drawPosition = this.drawPos;
      return;
    }
    const toNext = this.fromLeft ? xVp > this.panX : xVp < this.panX;
    if (!this.drawing) {
      if (toNext && !this.canTurn(1)) {
        this.panReady = false;
        this.allowPan = false;
        this.onOverscroll(1);
        return;
      }
      if (!toNext && !this.canTurn(-1)) {
        this.panReady = false;
        this.allowPan = false;
        this.onOverscroll(-1);
        return;
      }
      if (toNext) {
        this.pageMove = FlipMove.NEXT;
        if (!this.capture(this.midId)) {
          this.resetVisual();
          return;
        }
        this.hideCurrent = true;
      } else {
        this.pageMove = FlipMove.PREV;
        if (!this.capture(this.prevId)) {
          this.resetVisual();
          return;
        }
      }
      this.drawing = true;
      this.showCurl = true;
    }
    this.gestureMove = toNext ? FlipMove.NEXT : FlipMove.PREV;
    this.panX = xVp;
    this.model.drawState = FlipDrawState.MOVING;
    this.model.drawPosition = this.drawPos;
    this.model.positionX = this.algoX(xVp);
    this.model.positionY = this.getUIContext().vp2px(localY);
    this.model.isFinished = false;
    this.redraw();
  }

  private onPanEnd(): void {
    if (!this.allowPan) {
      this.allowPan = true;
      this.resetVisual();
      return;
    }
    if (!this.drawing) {
      this.panX = 0;
      this.panReady = false;
      return;
    }
    const num = FLIP_DISTANCE_FRACTION;
    if (this.gestureMove === FlipMove.PREV) {
      const xDiff = (this.pxW - this.model.positionX) / num;
      let yDiff = (0 - this.model.positionY) / num;
      if (this.drawPos === FlipDrawPos.BOTTOM) {
        yDiff = (this.pxH - this.model.positionY) / num;
      }
      this.armAuto(xDiff, yDiff);
    } else if (this.gestureMove === FlipMove.NEXT) {
      this.armAuto(FLIP_X_DIFF, 0);
    } else {
      this.finishGesture(false);
    }
    this.drawing = false;
  }

  private onViewClick(event: ClickEvent): void {
    if (!this.flipEnabled) {
      this.onCenterTap();
      return;
    }
    if (this.timeID !== -1) {
      this.finishGesture(true);
      return;
    }
    if (this.areaW <= 0 || this.pageCount <= 0) {
      this.onCenterTap();
      return;
    }
    const edge = this.tapMode === 'edge' ? 0.12 : 0.3;
    let dir = 0;
    if (this.tapMode === 'none') {
      this.onCenterTap();
      return;
    }
    if (this.tapMode === 'vertical') {
      const y = event.y / (this.areaH > 0 ? this.areaH : 1);
      if (y < 0.3) {
        dir = -1;
      } else if (y > 0.7) {
        dir = 1;
      }
    } else {
      const left = event.x < this.areaW * edge;
      const right = event.x > this.areaW * (1 - edge);
      if (left) {
        dir = this.nextOnLeft ? 1 : -1;
      } else if (right) {
        dir = this.nextOnLeft ? -1 : 1;
      }
    }
    if (dir === 0) {
      this.onCenterTap();
      return;
    }
    if (!this.canTurn(dir)) {
      this.onOverscroll(dir);
      return;
    }
    const move = dir > 0 ? FlipMove.NEXT : FlipMove.PREV;
    const snap = dir > 0 ? this.midId : this.prevId;
    const xPx = this.algoX(event.x);
    const yPx = this.getUIContext().vp2px(event.y);
    if (!this.beginCurl(move, xPx, yPx, snap)) {
      return;
    }
    if (move === FlipMove.PREV) {
      const xDiff = (this.pxW - xPx) / FLIP_DISTANCE_FRACTION;
      const yDiff = (0 - yPx) / FLIP_DISTANCE_FRACTION;
      this.armAuto(xDiff, yDiff);
    } else {
      this.armAuto(FLIP_X_DIFF, 0);
    }
  }

  @Builder
  pageSlot(index: number, slotId: string) {
    Column() {
      if (index >= 0 && index < this.pageCount) {
        this.pageContent(index)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
    .id(slotId)
  }

  build() {
    Stack() {
      this.pageSlot(this.page + 1, this.nextId)

      Column() {
        if (!this.hideCurrent) {
          this.pageSlot(this.page, this.midId)
        }
      }
      .width('100%')
      .height('100%')

      if (this.page > 0) {
        Column() {
          this.pageSlot(this.page - 1, this.prevId)
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.areaW > 0 ? -this.areaW : -2000 })
        .hitTestBehavior(HitTestMode.None)
      }

      NodeContainer(this.controller)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .visibility(this.showCurl ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.bgColor)
    .onAreaChange((_old: Area, neu: Area) => {
      const w = neu.width;
      const h = neu.height;
      if (typeof w === 'number' && typeof h === 'number' && w > 0 && h > 0) {
        this.areaW = w;
        this.areaH = h;
        this.pxW = this.getUIContext().vp2px(w);
        this.pxH = this.getUIContext().vp2px(h);
        this.controller.setSize(w, h);
        if (this.timeID !== -1 || this.drawing) {
          this.finishGesture(false);
        }
      }
    })
    .gesture(
      PanGesture({ fingers: 1 })
        .onActionUpdate((event: GestureEvent) => {
          if (event.fingerList.length <= 0) {
            return;
          }
          const finger = event.fingerList[0];
          this.onFinger(finger.localX, finger.localY);
        })
        .onActionEnd(() => {
          this.onPanEnd();
        })
        .onActionCancel(() => {
          this.finishGesture(false);
        })
    )
    .onClick((event: ClickEvent) => {
      this.onViewClick(event);
    })
  }
}
