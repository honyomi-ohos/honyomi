/*
 * HostCalls — 通用宿主调用桥（__nativeHostCall）的 ArkTS 侧路由。
 *
 * Native 引擎把插件的 (kind, payloadJson) 请求经 HTTP 任务通道投递到主线程
 * （msg.type === 'hostCall'），本模块按 kind 分发到具体宿主能力：
 *   cookieHeader / cookieGet / cookieSet  → CookieJar（域级持久 Cookie）
 *   imageDecode / imageEncodePng          → @ohos.image（像素级编解码）
 * dispatch 返回结果 JSON 字符串（信封 body），异常向上抛由桥接层转错误信封。
 * 运行时 shim 已校验载荷，此处独立再校验：防插件绕过 shim 手工打桥。
 */

import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { CookieJar } from '../net/CookieJar';

interface HostCallPayload {
  url?: string;
  name?: string;
  value?: string;
  bytesBase64?: string;
  width?: number;
  height?: number;
  pixelsBase64?: string;
}

interface CookieHeaderResult {
  header: string;
}

interface CookieGetResult {
  value: string;
}

interface ImageDecodeResult {
  width: number;
  height: number;
  pixelsBase64: string;
}

interface ImageEncodeResult {
  pngBase64: string;
}

// 图像桥载荷上限（与 runtime $ DSL 侧一致）
const IMAGE_BYTES_MAX = 64 * 1024 * 1024;
const IMAGE_PIXELS_MAX = 16 * 1024 * 1024;

export class HostCalls {
  /** 按 kind 路由宿主调用，返回结果 JSON（信封 body）。 */
  static async dispatch(kind: string, payloadJson: string): Promise<string> {
    let payload: HostCallPayload = {};
    try {
      const parsed = JSON.parse(payloadJson) as HostCallPayload;
      if (parsed !== null && parsed !== undefined && typeof parsed === 'object') {
        payload = parsed;
      }
    } catch (e) {
      throw new Error('host call payload 解析失败');
    }
    switch (kind) {
      case 'cookieHeader': {
        const url = HostCalls.requireHttpUrl(payload.url);
        const out: CookieHeaderResult = { header: CookieJar.headerFor(url) };
        return JSON.stringify(out);
      }
      case 'cookieGet': {
        const url = HostCalls.requireHttpUrl(payload.url);
        const name = HostCalls.requireCookieName(payload.name);
        const out: CookieGetResult = { value: CookieJar.getCookie(url, name) };
        return JSON.stringify(out);
      }
      case 'cookieSet': {
        const url = HostCalls.requireHttpUrl(payload.url);
        const name = HostCalls.requireCookieName(payload.name);
        const value = HostCalls.requireCookieValue(payload.value);
        CookieJar.storeOne(url, `${name}=${value}`);
        return '{}';
      }
      case 'imageDecode': {
        const b64 = payload.bytesBase64 ?? '';
        if (b64 === '') {
          throw new Error('图片解码失败: 空输入');
        }
        return await HostCalls.decodeImage(b64);
      }
      case 'imageEncodePng': {
        const w = payload.width ?? 0;
        const h = payload.height ?? 0;
        if (!Number.isInteger(w) || !Number.isInteger(h) || w <= 0 || h <= 0 ||
          w * h > IMAGE_PIXELS_MAX) {
          throw new Error(`图片编码失败: 尺寸非法 (${w}x${h})`);
        }
        const b64 = payload.pixelsBase64 ?? '';
        if (b64 === '') {
          throw new Error('图片编码失败: 空像素缓冲');
        }
        return await HostCalls.encodePng(w, h, b64);
      }
      default:
        throw new Error(`不支持的 host call: ${kind}`);
    }
  }

  // ------------------------------------------------------------------ private

  private static requireHttpUrl(url: string | undefined): string {
    const u = url ?? '';
    if (u.indexOf('https://') !== 0 && u.indexOf('http://') !== 0) {
      throw new Error(`仅支持 http/https 地址: ${u}`);
    }
    return u;
  }

  private static requireCookieName(name: string | undefined): string {
    const n = name ?? '';
    if (n === '' || /[\r\n\0;,=]/.test(n)) {
      throw new Error('非法 cookie 名');
    }
    return n;
  }

  private static requireCookieValue(value: string | undefined): string {
    const v = value ?? '';
    if (/[\r\n\0]/.test(v)) {
      throw new Error('非法 cookie 值');
    }
    return v;
  }

  // 图片字节 → {width, height, pixelsBase64}：RGBA_8888 解码，
  // readPixelsToBuffer 原始布局原样回传（与 encodePng 对称，通道序对
  // 解码→重排→回编的还原类拦截器无影响）
  private static async decodeImage(bytesBase64: string): Promise<string> {
    const bytes = new util.Base64Helper().decodeSync(bytesBase64);
    if (bytes.byteLength === 0) {
      throw new Error('图片解码失败: 空输入');
    }
    if (bytes.byteLength > IMAGE_BYTES_MAX) {
      throw new Error('图片解码失败: 输入过大');
    }
    const source = image.createImageSource(bytes);
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const info = await pixelMap.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (!Number.isInteger(w) || !Number.isInteger(h) || w <= 0 || h <= 0 ||
        w * h > IMAGE_PIXELS_MAX) {
        throw new Error(`图片解码失败: 尺寸超限 (${w}x${h})`);
      }
      const buf = new ArrayBuffer(w * h * 4);
      await pixelMap.readPixelsToBuffer(buf);
      const out: ImageDecodeResult = {
        width: w,
        height: h,
        pixelsBase64: new util.Base64Helper().encodeToStringSync(new Uint8Array(buf)),
      };
      return JSON.stringify(out);
    } finally {
      if (pixelMap !== undefined) {
        try {
          pixelMap.release();
        } catch (e) {
          /* cleanup only */
        }
      }
      try {
        source.release();
      } catch (e) {
        /* cleanup only */
      }
    }
  }

  // RGBA 像素（width*height*4 字节）→ PNG 字节（base64 回传）
  private static async encodePng(width: number, height: number, pixelsBase64: string): Promise<string> {
    const pixels = new util.Base64Helper().decodeSync(pixelsBase64);
    if (pixels.byteLength !== width * height * 4) {
      throw new Error('图片编码失败: 像素缓冲长度不匹配');
    }
    const pixelMap = await image.createPixelMap(pixels.buffer, {
      size: { width: width, height: height },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
    });
    const packer = image.createImagePacker();
    try {
      const opt: image.PackingOption = { format: 'image/png', quality: 100 };
      const packed = await packer.packToData(pixelMap, opt);
      const out: ImageEncodeResult = {
        pngBase64: new util.Base64Helper().encodeToStringSync(new Uint8Array(packed)),
      };
      return JSON.stringify(out);
    } finally {
      try {
        packer.release();
      } catch (e) {
        /* cleanup only */
      }
      try {
        pixelMap.release();
      } catch (e) {
        /* cleanup only */
      }
    }
  }
}
