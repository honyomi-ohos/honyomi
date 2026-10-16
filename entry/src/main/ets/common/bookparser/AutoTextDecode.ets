// 文本文件自动解码（纯逻辑，无 UI 依赖）：BOM 识别 + UTF-8/GB18030/GBK/Big5 严格模式探测链。
// 自 Util.readTextAuto 移植为独立模块：taskpool @Concurrent 任务只能引用 import 变量，
// 章节文本解码（本地 txt / 书籍章节缓存）在 taskpool 线程执行时经此复用。

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class AutoTextDecode {
  // 智能读取文本文件：自动识别 UTF-8/UTF-16(BOM)/GB18030/GBK/Big5，避免中文乱码
  static readFileAuto(path: string): string {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const size: number = fs.statSync(file.fd).size;
        if (size <= 0) {
          return '';
        }
        const buf: ArrayBuffer = new ArrayBuffer(size);
        const read: number = fs.readSync(file.fd, buf);
        return AutoTextDecode.decodeBytes(new Uint8Array(buf, 0, read));
      } finally {
        try {
          fs.closeSync(file);
        } catch (_e) {
        }
      }
    } catch (e) {
      throw new Error(`read text file failed: ${e}`);
    }
  }

  // 字节流解码：BOM 优先，随后依次以严格模式尝试 UTF-8/GB18030/GBK/Big5，全部失败回退宽松 UTF-8
  static decodeBytes(bytes: Uint8Array): string {
    if (bytes.length === 0) {
      return '';
    }
    if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
      return AutoTextDecode.cleanText(AutoTextDecode.decodeWith('utf-16le', bytes.subarray(2)));
    }
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      return AutoTextDecode.cleanText(AutoTextDecode.decodeWith('utf-16be', bytes.subarray(2)));
    }
    try {
      return AutoTextDecode.cleanText(AutoTextDecode.decodeWith('utf-8', bytes));
    } catch (e) {
      // 非 UTF-8，继续尝试中文编码
    }
    try {
      return AutoTextDecode.cleanText(AutoTextDecode.decodeWith('gb18030', bytes));
    } catch (e) {
      // 非 GB18030
    }
    try {
      return AutoTextDecode.cleanText(AutoTextDecode.decodeWith('gbk', bytes));
    } catch (e) {
      // 非 GBK
    }
    try {
      return AutoTextDecode.cleanText(AutoTextDecode.decodeWith('big5', bytes));
    } catch (e) {
      // 非 Big5
    }
    return AutoTextDecode.cleanText(AutoTextDecode.decodeWith('utf-8', bytes));
  }

  // 统一换行符为 \n，并去除解码残留的 BOM 字符
  static cleanText(text: string): string {
    return text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }

  private static decodeWith(encoding: string, data: Uint8Array): string {
    const options: util.TextDecoderOptions = { fatal: true, ignoreBOM: false };
    return util.TextDecoder.create(encoding, options).decodeToString(data);
  }
}
