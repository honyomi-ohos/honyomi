/*
 * HostCalls — 通用宿主调用桥（__nativeHostCall）的 ArkTS 侧路由。
 *
 * Native 引擎把插件的 (kind, payloadJson) 请求经 HTTP 任务通道投递到主线程
 * （msg.type === 'hostCall'），本模块按 kind 分发到具体宿主能力：
 *   cookieHeader / cookieGet / cookieSet  → CookieJar（域级持久 Cookie）
 *   imageDecode / imageEncodePng / imageEncodeJpeg → @ohos.image（像素级编解码）
 *   aesCbc / aesGcm / aesCtr              → CryptoArchitectureKit（插件 AES）
 * dispatch 返回结果 JSON 字符串（信封 body），异常向上抛由桥接层转错误信封。
 * 运行时 shim 已校验载荷，此处独立再校验：防插件绕过 shim 手工打桥。
 */

import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CookieJar } from '../net/CookieJar';
import { PluginHostCrypto } from './PluginHostCrypto';

const HOST_CALLS_DOMAIN: number = 0x0000;
const HOST_CALLS_TAG: string = 'HostCalls';

interface HostCallPayload {
  url?: string;
  name?: string;
  value?: string;
  bytesBase64?: string;
  width?: number;
  height?: number;
  pixelsBase64?: string;
  quality?: number;
  // AES 桥：data/key/iv/aad 均为 base64；decrypt 缺省 true
  dataBase64?: string;
  keyBase64?: string;
  ivBase64?: string;
  aadBase64?: string;
  decrypt?: boolean;
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

interface ImageEncodeJpegResult {
  jpegBase64: string;
}

interface AesResult {
  dataBase64: string;
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
        return await HostCalls.encodePacked(w, h, b64, 'image/png', 100, 'png');
      }
      case 'imageEncodeJpeg': {
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
        let q = payload.quality ?? 90;
        if (!Number.isFinite(q)) {
          q = 90;
        }
        q = Math.floor(q);
        if (q < 1) {
          q = 1;
        } else if (q > 100) {
          q = 100;
        }
        return await HostCalls.encodePacked(w, h, b64, 'image/jpeg', q, 'jpeg');
      }
      case 'aesCbc': {
        return HostCalls.aesResult(
          PluginHostCrypto.aesCbc(
            HostCalls.decodeB64('aes', payload.dataBase64),
            HostCalls.decodeB64('aes', payload.keyBase64),
            HostCalls.decodeB64('aes', payload.ivBase64),
            payload.decrypt !== false,
          ),
        );
      }
      case 'aesGcm': {
        const aad = payload.aadBase64 !== undefined && payload.aadBase64 !== ''
          ? HostCalls.decodeB64('aes-gcm', payload.aadBase64)
          : new Uint8Array(0);
        return HostCalls.aesResult(
          PluginHostCrypto.aesGcm(
            HostCalls.decodeB64('aes-gcm', payload.dataBase64),
            HostCalls.decodeB64('aes-gcm', payload.keyBase64),
            HostCalls.decodeB64('aes-gcm', payload.ivBase64),
            aad,
            payload.decrypt !== false,
          ),
        );
      }
      case 'aesCtr': {
        return HostCalls.aesResult(
          PluginHostCrypto.aesCtr(
            HostCalls.decodeB64('aes-ctr', payload.dataBase64),
            HostCalls.decodeB64('aes-ctr', payload.keyBase64),
            HostCalls.decodeB64('aes-ctr', payload.ivBase64),
            payload.decrypt !== false,
          ),
        );
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


  private static decodeB64(prefix: string, b64: string | undefined): Uint8Array {
    const s = b64 ?? '';
    if (s === '') {
      throw new Error(`${prefix}: empty base64`);
    }
    try {
      return new util.Base64Helper().decodeSync(s);
    } catch (e) {
      throw new Error(`${prefix}: invalid base64`);
    }
  }

  private static aesResult(data: Uint8Array): string {
    const out: AesResult = {
      dataBase64: new util.Base64Helper().encodeToStringSync(data),
    };
    return JSON.stringify(out);
  }

  // 图片字节 → {width, height, pixelsBase64}：RGBA_8888 解码。
  // readPixelsToBuffer 原始布局原样回传（与 encodePng 对称，通道序对
  // 解码→重排→回编的还原类拦截器无影响）。
  // 加固：createImageSource 只接受 ArrayBuffer（传 Uint8Array 会得到 undefined，
  // 再调 createPixelMap 即 "createPixelMap of undefined"）；失败返回稳定错误串，
  // 永不对 undefined 调 createPixelMap。AVIF 不在此特判（真机系统可解；
  // 模拟器 AVIF 已知不可用，见 AvifConverter，P2 不做插件侧接入）。
  private static async decodeImage(bytesBase64: string): Promise<string> {
    let bytes: Uint8Array;
    try {
      bytes = new util.Base64Helper().decodeSync(bytesBase64);
    } catch (e) {
      throw new Error('图片解码失败: invalid base64');
    }
    if (bytes.byteLength === 0) {
      throw new Error('图片解码失败: 空输入');
    }
    if (bytes.byteLength > IMAGE_BYTES_MAX) {
      throw new Error('图片解码失败: 输入过大');
    }
    // 拷贝出独立 ArrayBuffer：@ohos.image 要 ArrayBuffer（传 Uint8Array 会得到 null/undefined）
    const ab = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(ab).set(bytes);
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(ab);
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      hilog.warn(HOST_CALLS_DOMAIN, HOST_CALLS_TAG,
        'imageDecode createImageSource throw len=%{public}d err=%{public}s',
        bytes.byteLength, msg);
      throw new Error(`图片解码失败: createImageSource (${msg})`);
    }
    // createImageSource 失败时可能返回 null 或 undefined，二者都要拦
    if (source === undefined || (source as Object | null) === null) {
      hilog.warn(HOST_CALLS_DOMAIN, HOST_CALLS_TAG,
        'imageDecode createImageSource empty len=%{public}d', bytes.byteLength);
      throw new Error('图片解码失败: createImageSource returned empty');
    }
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      try {
        pixelMap = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      } catch (e) {
        const msg = e instanceof Error ? e.message : `${e}`;
        hilog.warn(HOST_CALLS_DOMAIN, HOST_CALLS_TAG,
          'imageDecode createPixelMap throw len=%{public}d err=%{public}s',
          bytes.byteLength, msg);
        throw new Error(`图片解码失败: createPixelMap (${msg})`);
      }
      if (pixelMap === undefined || (pixelMap as Object | null) === null) {
        hilog.warn(HOST_CALLS_DOMAIN, HOST_CALLS_TAG,
          'imageDecode createPixelMap empty len=%{public}d', bytes.byteLength);
        throw new Error('图片解码失败: createPixelMap returned empty');
      }
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

  // RGBA 像素（width*height*4 字节）→ PNG/JPEG 字节（base64 回传）
  // format: 'image/png' | 'image/jpeg'；resultKind: 'png' → pngBase64，'jpeg' → jpegBase64
  private static async encodePacked(
    width: number,
    height: number,
    pixelsBase64: string,
    format: string,
    quality: number,
    resultKind: string,
  ): Promise<string> {
    let pixels: Uint8Array;
    try {
      pixels = new util.Base64Helper().decodeSync(pixelsBase64);
    } catch (e) {
      throw new Error('图片编码失败: invalid base64');
    }
    if (pixels.byteLength !== width * height * 4) {
      throw new Error('图片编码失败: 像素缓冲长度不匹配');
    }
    const ab = new ArrayBuffer(pixels.byteLength);
    new Uint8Array(ab).set(pixels);
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await image.createPixelMap(ab, {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      hilog.warn(HOST_CALLS_DOMAIN, HOST_CALLS_TAG,
        'imageEncode createPixelMap throw format=%{public}s err=%{public}s', format, msg);
      throw new Error(`图片编码失败: createPixelMap (${msg})`);
    }
    if (pixelMap === undefined || (pixelMap as Object | null) === null) {
      throw new Error('图片编码失败: createPixelMap returned empty');
    }
    const packer = image.createImagePacker();
    try {
      const opt: image.PackingOption = { format: format, quality: quality };
      const packed = await packer.packToData(pixelMap, opt);
      const b64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(packed));
      if (resultKind === 'jpeg') {
        const out: ImageEncodeJpegResult = { jpegBase64: b64 };
        return JSON.stringify(out);
      }
      const out: ImageEncodeResult = { pngBase64: b64 };
      return JSON.stringify(out);
    } catch (e) {
      const err = e as Error;
      throw err;
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
