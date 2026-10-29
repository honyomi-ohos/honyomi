import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StripImagePipeline } from '../common/StripImagePipeline';
import { TranslationService } from './TranslationService';
import { LangDetect } from './LangDetect';

// 漫画页 OCR 译文框：坐标为解码后图像的像素坐标（左上原点），bg/fg 为叠加层配色
export class OcrTextBox {
  x: number;
  y: number;
  w: number;
  h: number;
  text: string;
  bg: string;
  fg: string;

  constructor(x: number, y: number, w: number, h: number, text: string, bg: string, fg: string) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.text = text;
    this.bg = bg;
    this.fg = fg;
  }
}

// 单页 OCR + 翻译结果：解码图像尺寸 + 译文框列表
export class PageTransData {
  imgW: number;
  imgH: number;
  boxes: OcrTextBox[];

  constructor(imgW: number, imgH: number, boxes: OcrTextBox[]) {
    this.imgW = imgW;
    this.imgH = imgH;
    this.boxes = boxes;
  }
}

// 空数据（未翻译/无文字页的占位，供组件属性兜底）
export const EMPTY_TRANS: PageTransData = new PageTransData(1, 1, []);

// OCR 文本块中间结构：块内文本行并集外接矩形 + 原文
class OcrUnit {
  x1: number = 0;
  y1: number = 0;
  x2: number = 0;
  y2: number = 0;
  text: string = '';
}

// 漫画图片翻译：CoreVisionKit 文字识别（zh-CN/en/ja/ko/zh-TW，含竖排日文）→
// 按文本块整段翻译（避免逐行断句）→ 采样气泡底色生成叠加数据
export class MangaOcrTranslator {
  private static refCount: number = 0;
  private static inited: boolean = false;

  // OCR 服务引用计数：首个使用方 init（含超时重试），最后一个使用方 release
  static async retain(): Promise<boolean> {
    if (MangaOcrTranslator.refCount === 0 && !MangaOcrTranslator.inited) {
      if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
        hilog.warn(0x0001, 'MangaOcr', 'ocr syscap not supported on this device');
        return false;
      }
      // 首次超时可能是服务冷启动，间隔 2s 重试一次
      for (let attempt = 0; attempt < 2 && !MangaOcrTranslator.inited; attempt++) {
        try {
          MangaOcrTranslator.inited = await textRecognition.init();
        } catch (e) {
          hilog.warn(0x0001, 'MangaOcr', 'ocr init failed (attempt %{public}d): %{public}s', `${attempt + 1}`,
            e instanceof Error ? e.message : String(e));
          MangaOcrTranslator.inited = false;
        }
        if (!MangaOcrTranslator.inited && attempt === 0) {
          await MangaOcrTranslator.delay(2000);
        }
      }
    }
    if (!MangaOcrTranslator.inited) {
      return false;
    }
    MangaOcrTranslator.refCount += 1;
    return true;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  static async release(): Promise<void> {
    if (MangaOcrTranslator.refCount > 0) {
      MangaOcrTranslator.refCount -= 1;
    }
    if (MangaOcrTranslator.refCount === 0 && MangaOcrTranslator.inited) {
      MangaOcrTranslator.inited = false;
      try {
        await textRecognition.release();
      } catch (_e) {
      }
    }
  }

  // 单页 OCR + 翻译：返回译文叠加数据（无文字页 boxes 为空）；
  // 页面语言与目标语言一致时返回 null（调用方据此跳过/终止翻译流程）
  static async translateImage(url: string, sourceKey: string, pageUrl: string, to: string,
    shouldStop: () => boolean): Promise<PageTransData | null> {
    // RGBA_8888 专用解码（CoreVisionKit 仅支持该格式），不占用条漫内存缓存
    const pm: image.PixelMap = await StripImagePipeline.loadForOcr(url, sourceKey, pageUrl);
    try {
      const info: image.ImageInfo = await pm.getImageInfo();
      const imgW: number = info.size.width;
      const imgH: number = info.size.height;
      if (imgW <= 0 || imgH <= 0) {
        return new PageTransData(1, 1, []);
      }
      const visionInfo: textRecognition.VisionInfo = { pixelMap: pm };
      const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(visionInfo);
      const units: OcrUnit[] = MangaOcrTranslator.collectUnits(result, imgW, imgH);
      if (units.length === 0) {
        return new PageTransData(imgW, imgH, []);
      }
      const texts: string[] = [];
      for (const unit of units) {
        texts.push(unit.text);
      }
      // 翻译前判断当前语言与目标语言：一致则不触发翻译
      if (LangDetect.sameLang(texts.join('\n'), to)) {
        return null;
      }
      const translated: string[] = await TranslationService.translatePage(texts, 'auto', to);
      if (shouldStop()) {
        return new PageTransData(imgW, imgH, []);
      }
      // 一次性读回像素用于气泡底色采样（RGBA 连续内存）
      const buffer: ArrayBuffer = new ArrayBuffer(imgW * imgH * 4);
      await pm.readPixelsToBuffer(buffer);
      const pixels: Uint8Array = new Uint8Array(buffer);
      const boxes: OcrTextBox[] = [];
      for (let i = 0; i < units.length; i++) {
        const unit: OcrUnit = units[i];
        const out: string = translated[i] === '' ? unit.text : translated[i];
        const bg: string = MangaOcrTranslator.sampleBg(pixels, imgW, imgH, unit);
        boxes.push(new OcrTextBox(unit.x1, unit.y1, unit.x2 - unit.x1, unit.y2 - unit.y1,
          out, bg, MangaOcrTranslator.fgOf(bg)));
      }
      return new PageTransData(imgW, imgH, boxes);
    } finally {
      pm.release().catch((_e: Object) => {
      });
    }
  }

  // 文本块 → 翻译单元：块内文本行 cornerPoints 并集外接矩形，外扩 6% 框高遮住笔画
  private static collectUnits(result: textRecognition.TextRecognitionResult,
    imgW: number, imgH: number): OcrUnit[] {
    const units: OcrUnit[] = [];
    for (const block of result.blocks) {
      let text: string = block.value;
      let x1: number = -1;
      let y1: number = -1;
      let x2: number = -1;
      let y2: number = -1;
      for (const line of block.lines) {
        for (const pt of line.cornerPoints) {
          if (x1 < 0 || pt.x < x1) {
            x1 = pt.x;
          }
          if (y1 < 0 || pt.y < y1) {
            y1 = pt.y;
          }
          if (pt.x > x2) {
            x2 = pt.x;
          }
          if (pt.y > y2) {
            y2 = pt.y;
          }
        }
      }
      if (text === '') {
        const parts: string[] = [];
        for (const line of block.lines) {
          parts.push(line.value);
        }
        text = parts.join('');
      }
      if (text.trim() === '' || x1 < 0 || x2 <= x1 || y2 <= y1) {
        continue;
      }
      const pad: number = Math.min(8, Math.max(2, (y2 - y1) * 0.06));
      const unit: OcrUnit = new OcrUnit();
      unit.x1 = Math.max(0, x1 - pad);
      unit.y1 = Math.max(0, y1 - pad);
      unit.x2 = Math.min(imgW - 1, x2 + pad);
      unit.y2 = Math.min(imgH - 1, y2 + pad);
      unit.text = text;
      units.push(unit);
    }
    return units;
  }

  // 气泡底色采样：文本框外扩 3px 的四角与四边中点共 8 点取 RGB 均值
  private static sampleBg(pixels: Uint8Array, imgW: number, imgH: number, unit: OcrUnit): string {
    const off: number = 3;
    const midX: number = (unit.x1 + unit.x2) / 2;
    const midY: number = (unit.y1 + unit.y2) / 2;
    const samples: number[][] = [
      [unit.x1 - off, unit.y1 - off], [unit.x2 + off, unit.y1 - off],
      [unit.x1 - off, unit.y2 + off], [unit.x2 + off, unit.y2 + off],
      [midX, unit.y1 - off], [midX, unit.y2 + off],
      [unit.x1 - off, midY], [unit.x2 + off, midY]
    ];
    let r: number = 0;
    let g: number = 0;
    let b: number = 0;
    let n: number = 0;
    for (const sample of samples) {
      const px: number = Math.min(imgW - 1, Math.max(0, Math.round(sample[0])));
      const py: number = Math.min(imgH - 1, Math.max(0, Math.round(sample[1])));
      const idx: number = (py * imgW + px) * 4;
      if (idx + 2 >= pixels.length) {
        continue;
      }
      r += pixels[idx];
      g += pixels[idx + 1];
      b += pixels[idx + 2];
      n += 1;
    }
    if (n === 0) {
      return '#F0FFFFFF';
    }
    return `#F0${MangaOcrTranslator.hex2(Math.round(r / n))}` +
      `${MangaOcrTranslator.hex2(Math.round(g / n))}${MangaOcrTranslator.hex2(Math.round(b / n))}`;
  }

  // 前景色随底色亮度取高对比深/浅色
  private static fgOf(bg: string): string {
    const r: number = parseInt(bg.substring(3, 5), 16);
    const g: number = parseInt(bg.substring(5, 7), 16);
    const b: number = parseInt(bg.substring(7, 9), 16);
    const lum: number = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return lum > 0.55 ? '#EE151515' : '#F2FFFFFF';
  }

  private static hex2(v: number): string {
    const s: string = v.toString(16).toUpperCase();
    return s.length < 2 ? `0${s}` : s;
  }
}
