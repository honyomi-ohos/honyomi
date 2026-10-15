// 字节读写工具（书籍解析底层）：大端读取器、可增长字节缓冲、文件 IO、解码助手。
// 纯逻辑无 UI 依赖，可在 taskpool 中使用。

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// 大端字节读取器：按位序依次读取 u8/u16/u32/ascii/bytes
export class ByteReader {
  readonly bytes: Uint8Array;
  pos: number = 0;

  constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  u8(): number {
    const v = this.bytes[this.pos];
    this.pos += 1;
    return v;
  }

  u16(): number {
    const v = (this.bytes[this.pos] << 8) | this.bytes[this.pos + 1];
    this.pos += 2;
    return v;
  }

  u32(): number {
    const b = this.bytes;
    const p = this.pos;
    const v = ((b[p] * 256 + b[p + 1]) * 256 + b[p + 2]) * 256 + b[p + 3];
    this.pos += 4;
    return v;
  }

  ascii(len: number): string {
    let out = '';
    for (let i = 0; i < len; i++) {
      out += String.fromCharCode(this.bytes[this.pos + i]);
    }
    this.pos += len;
    return out;
  }

  readBytes(len: number): Uint8Array {
    const v = this.bytes.subarray(this.pos, this.pos + len);
    this.pos += len;
    return v;
  }

  skip(n: number): void {
    this.pos += n;
  }

  remaining(): number {
    return this.bytes.length - this.pos;
  }
}

// 可增长字节缓冲（PalmDOC/HUFF 解压输出）
export class ByteBuilder {
  private buf: Uint8Array;
  private len: number = 0;

  constructor(cap: number) {
    this.buf = new Uint8Array(cap > 0 ? cap : 1024);
  }

  get length(): number {
    return this.len;
  }

  byteAt(index: number): number {
    return this.buf[index];
  }

  appendByte(v: number): void {
    this.ensure(1);
    this.buf[this.len] = v & 0xFF;
    this.len += 1;
  }

  appendBytes(src: Uint8Array, start: number, count: number): void {
    if (count <= 0) {
      return;
    }
    this.ensure(count);
    for (let i = 0; i < count; i++) {
      this.buf[this.len + i] = src[start + i];
    }
    this.len += count;
  }

  toUint8Array(): Uint8Array {
    return this.buf.subarray(0, this.len);
  }

  private ensure(extra: number): void {
    if (this.len + extra <= this.buf.length) {
      return;
    }
    let cap = this.buf.length * 2;
    while (cap < this.len + extra) {
      cap *= 2;
    }
    const next = new Uint8Array(cap);
    next.set(this.buf.subarray(0, this.len));
    this.buf = next;
  }
}

// 无符号大端读取静态助手
export class ByteUtils {
  static u16At(b: Uint8Array, off: number): number {
    return (b[off] << 8) | b[off + 1];
  }

  static u32At(b: Uint8Array, off: number): number {
    return ((b[off] * 256 + b[off + 1]) * 256 + b[off + 2]) * 256 + b[off + 3];
  }

  static asciiAt(b: Uint8Array, off: number, len: number): string {
    let out = '';
    const end = Math.min(off + len, b.length);
    for (let i = off; i < end; i++) {
      out += String.fromCharCode(b[i]);
    }
    return out;
  }

  static startsWithAscii(b: Uint8Array, off: number, expect: string): boolean {
    if (off + expect.length > b.length) {
      return false;
    }
    for (let i = 0; i < expect.length; i++) {
      if (b[off + i] !== expect.charCodeAt(i)) {
        return false;
      }
    }
    return true;
  }

  // 2 的幂（32 位大整数移位等价：避免 JS 32 位符号截断）
  static pow2(n: number): number {
    return Math.pow(2, n);
  }
}

// 文件 IO 助手（书籍解析专用，独立于 common/Util 以避免 UI 依赖链）
export class BookFileIo {
  // 读取整个文件为字节数组；不存在返回 null
  static readBytes(path: string): Uint8Array | null {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const size: number = fs.statSync(file.fd).size;
        if (size <= 0) {
          return new Uint8Array(0);
        }
        const buf: ArrayBuffer = new ArrayBuffer(size);
        const read: number = fs.readSync(file.fd, buf);
        return new Uint8Array(buf, 0, read);
      } finally {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
    } catch (e) {
      return null;
    }
  }

  static writeBytes(path: string, data: Uint8Array): void {
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const buf: ArrayBuffer = new ArrayBuffer(data.length);
      new Uint8Array(buf).set(data);
      fs.writeSync(file.fd, buf);
    } finally {
      fs.closeSync(file);
    }
  }

  static writeText(path: string, text: string): void {
    const bytes: Uint8Array = BookTextCodec.encodeUtf8(text);
    BookFileIo.writeBytes(path, bytes);
  }

  static readText(path: string): string | null {
    const bytes = BookFileIo.readBytes(path);
    if (bytes === null) {
      return null;
    }
    return BookTextCodec.decodeUtf8(bytes);
  }

  // 只读文件头部若干字节（格式嗅探用，避免大文件整读）
  static readHead(path: string, len: number): Uint8Array | null {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const size: number = fs.statSync(file.fd).size;
        if (size <= 0) {
          return new Uint8Array(0);
        }
        const want: number = Math.min(len, size);
        const buf: ArrayBuffer = new ArrayBuffer(want);
        const read: number = fs.readSync(file.fd, buf);
        return new Uint8Array(buf, 0, read);
      } finally {
        try {
          fs.closeSync(file);
        } catch (e) {
        }
      }
    } catch (e) {
      return null;
    }
  }

  static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  static ensureDir(path: string): void {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  }

  static removeQuietly(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.rmdirSync(path);
      }
    } catch (e) {
    }
  }

  static fileSize(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (e) {
      return 0;
    }
  }

  static mtime(path: string): number {
    try {
      return fs.statSync(path).mtime;
    } catch (e) {
      return 0;
    }
  }
}

// 文本编码助手：UTF-8 严格/宽松解码、XML 声明感知解码、cp1252 手工解码兜底
export class BookTextCodec {
  static encodeUtf8(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text);
  }

  static decodeUtf8(bytes: Uint8Array): string {
    try {
      const opts: util.TextDecoderOptions = { fatal: false, ignoreBOM: false };
      return util.TextDecoder.create('utf-8', opts).decodeToString(bytes);
    } catch (e) {
      return '';
    }
  }

  // 按编码名解码；编码不可用（TextDecoder 不支持）返回 null 由调用方兜底
  static decodeWith(bytes: Uint8Array, encoding: string, fatal: boolean): string | null {
    try {
      const opts: util.TextDecoderOptions = { fatal: fatal, ignoreBOM: false };
      return util.TextDecoder.create(encoding, opts).decodeToString(bytes);
    } catch (e) {
      return null;
    }
  }

  // xml/html 字节流解码：优先 XML 声明 encoding，默认宽松 UTF-8，失败回退 BOM/GBK 链
  static decodeXml(bytes: Uint8Array): string {
    const head = ByteUtils.asciiAt(bytes, 0, Math.min(200, bytes.length));
    const m = /encoding\s*=\s*["']([A-Za-z0-9._-]+)["']/i.exec(head);
    if (m !== null) {
      const enc = m[1].toLowerCase();
      if (enc !== 'utf-8' && enc !== 'utf8') {
        const decoded = BookTextCodec.decodeWith(bytes, enc, false);
        if (decoded !== null) {
          return decoded;
        }
      }
    }
    return BookTextCodec.decodeUtf8(bytes);
  }

  // cp1252（MOBI codepage 1252 常见）：TextDecoder 不支持时手工解码
  static decodeCp1252(bytes: Uint8Array): string {
    const special: number[] = [0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
      0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
      0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
      0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178];
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      const b = bytes[i];
      if (b < 0x80) {
        out += String.fromCharCode(b);
      } else if (b < 0xA0) {
        out += String.fromCharCode(special[b - 0x80]);
      } else {
        out += String.fromCharCode(b);
      }
    }
    return out;
  }

  // MOBI codepage 字节流解码（65001=UTF-8 / 1252=cp1252 / 其他按名尝试）
  static decodeMobi(bytes: Uint8Array, codepage: number): string {
    if (codepage === 65001) {
      return BookTextCodec.decodeUtf8(bytes);
    }
    if (codepage === 1252) {
      const decoded = BookTextCodec.decodeWith(bytes, 'windows-1252', false);
      if (decoded !== null) {
        return decoded;
      }
      return BookTextCodec.decodeCp1252(bytes);
    }
    const byName = BookTextCodec.decodeWith(bytes, `cp${codepage}`, false);
    if (byName !== null) {
      return byName;
    }
    const gbk = BookTextCodec.decodeWith(bytes, 'gb18030', false);
    if (gbk !== null) {
      return gbk;
    }
    return BookTextCodec.decodeUtf8(bytes);
  }
}
