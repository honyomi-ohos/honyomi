// MOBI 记录解压：PalmDOC(LZ77) 与 HUFF/CDIC。
// 算法口径对齐 KindleUnpack / calibre 的等价开源实现（mobi_uncompress.py / huffcdic.py）。
// 纯字节逻辑，无 UI 依赖，taskpool 可用。

import { ByteBuilder, ByteUtils } from './ByteUtils';

// PalmDOC LZ77 解压（compression = 2）
export class PalmdocDecoder {
  static decode(input: Uint8Array): Uint8Array {
    const out = new ByteBuilder(input.length * 3 + 4096);
    const total = input.length;
    let p = 0;
    while (p < total) {
      const c = input[p];
      p += 1;
      if (c >= 1 && c <= 8) {
        // 1..8：后续 c 字节为字面量
        const count = Math.min(c, total - p);
        out.appendBytes(input, p, count);
        p += c;
      } else if (c < 128) {
        // 0 或 9..127：单字节字面量
        out.appendByte(c);
      } else if (c >= 192) {
        // 192..255：空格 + (c ^ 0x80)
        out.appendByte(0x20);
        out.appendByte(c ^ 0x80);
      } else if (p < total) {
        // 128..191：距离/长度对
        const pair = (c << 8) | input[p];
        p += 1;
        const dist = (pair >> 3) & 0x07FF;
        const len = (pair & 7) + 3;
        if (dist > len) {
          // 不重叠：从固定起点整体拷贝
          const srcStart = out.length - dist;
          if (srcStart >= 0) {
            for (let i = 0; i < len; i++) {
              out.appendByte(out.byteAt(srcStart + i));
            }
          }
        } else if (dist > 0) {
          // 重叠拷贝：逐字节跟随输出末端
          for (let i = 0; i < len; i++) {
            const src = out.length - dist;
            if (src < 0) {
              break;
            }
            out.appendByte(out.byteAt(src));
          }
        }
      }
    }
    return out.toUint8Array();
  }
}

// HUFF/CDIC 解压器（compression = 17480 / 0x4448）：
// HUFF 记录携带 256 项缓存表（dict1）与 64 项基表（dict2），
// CDIC 记录携带字典短语表；解压按位读取 Huffman 编码索引短语并拼接。
export class HuffCdicDecoder {
  private codelens: number[] = [];
  private terms: boolean[] = [];
  private maxcodes: number[] = [];
  private mincodeByLen: number[] = [];
  private maxcodeByLen: number[] = [];
  private dicData: Uint8Array[] = [];
  private dicFlags: boolean[] = [];

  // 64 位窗口（xHi:xLo）右移 n 位取低 32 位（全 double 运算避免 32 位符号截断）
  private static codeWindow(xHi: number, xLo: number, n: number): number {
    if (n >= 32) {
      return Math.floor(xHi / ByteUtils.pow2(n - 32));
    }
    const hiPart = (xHi % ByteUtils.pow2(n)) * ByteUtils.pow2(32 - n);
    return hiPart + Math.floor(xLo / ByteUtils.pow2(n));
  }

  private static u32Safe(b: Uint8Array, off: number): number {
    if (off < 0 || off + 4 > b.length) {
      return 0;
    }
    return ByteUtils.u32At(b, off);
  }

  // 载入 HUFF 记录（第一段）
  loadHuff(huff: Uint8Array): void {
    if (huff.length < 0x120 || !ByteUtils.startsWithAscii(huff, 0, 'HUFF')) {
      throw new Error('invalid_huff_header');
    }
    const off1 = ByteUtils.u32At(huff, 8);
    const off2 = ByteUtils.u32At(huff, 12);
    if (off1 + 1024 > huff.length || off2 + 256 > huff.length) {
      throw new Error('invalid_huff_table');
    }
    this.codelens = [];
    this.terms = [];
    this.maxcodes = [];
    for (let i = 0; i < 256; i++) {
      const v = ByteUtils.u32At(huff, off1 + 4 * i);
      const codelen = v & 0x1F;
      if (codelen === 0) {
        throw new Error('invalid_huff_codelen');
      }
      const term = (v & 0x80) !== 0;
      const maxcode = ((v >>> 8) + 1) * ByteUtils.pow2(32 - codelen) - 1;
      this.codelens.push(codelen);
      this.terms.push(term);
      this.maxcodes.push(maxcode);
    }
    this.mincodeByLen = [0];
    this.maxcodeByLen = [0];
    for (let codelen = 1; codelen <= 32; codelen++) {
      const mn = ByteUtils.u32At(huff, off2 + 8 * (codelen - 1));
      const mx = ByteUtils.u32At(huff, off2 + 8 * (codelen - 1) + 4);
      this.mincodeByLen.push(mn * ByteUtils.pow2(32 - codelen));
      this.maxcodeByLen.push((mx + 1) * ByteUtils.pow2(32 - codelen) - 1);
    }
    this.dicData = [];
    this.dicFlags = [];
  }

  // 载入 CDIC 记录（后续若干段）
  loadCdic(cdic: Uint8Array): void {
    if (cdic.length < 16 || !ByteUtils.startsWithAscii(cdic, 0, 'CDIC')) {
      throw new Error('invalid_cdic_header');
    }
    const phrases = ByteUtils.u32At(cdic, 8);
    const bits = ByteUtils.u32At(cdic, 12);
    let n = ByteUtils.pow2(bits);
    const remain = phrases - this.dicData.length;
    if (n > remain) {
      n = remain;
    }
    const maxByData = Math.floor((cdic.length - 16) / 2);
    if (n > maxByData) {
      n = maxByData;
    }
    for (let i = 0; i < n; i++) {
      const off = ByteUtils.u16At(cdic, 16 + 2 * i);
      const blen = ByteUtils.u16At(cdic, 16 + off);
      const slice = cdic.subarray(18 + off, 18 + off + (blen & 0x7FFF));
      this.dicData.push(slice);
      this.dicFlags.push((blen & 0x8000) !== 0);
    }
  }

  // 解压单条文本记录（状态全局部化，支持字典短语递归展开）
  unpack(input: Uint8Array): Uint8Array {
    // 尾部补 8 字节零，保证 64 位滑动窗口读不越界
    const padded = new Uint8Array(input.length + 8);
    padded.set(input);
    const total = input.length;
    let pos = 0;
    let xHi = HuffCdicDecoder.u32Safe(padded, 0);
    let xLo = HuffCdicDecoder.u32Safe(padded, 4);
    let bitsLeft = total * 8;
    let n = 32;
    const out = new ByteBuilder(total * 4 + 1024);
    while (true) {
      if (n <= 0) {
        pos += 4;
        xHi = HuffCdicDecoder.u32Safe(padded, pos);
        xLo = HuffCdicDecoder.u32Safe(padded, pos + 4);
        n += 32;
      }
      const code = HuffCdicDecoder.codeWindow(xHi, xLo, n);
      const prefix = Math.floor(code / ByteUtils.pow2(24));
      let codelen = this.codelens[prefix];
      let term = this.terms[prefix];
      let maxcode = this.maxcodes[prefix];
      if (!term) {
        while (code < this.mincodeByLen[codelen]) {
          codelen += 1;
          if (codelen >= this.mincodeByLen.length) {
            throw new Error('invalid_huff_code');
          }
        }
        maxcode = this.maxcodeByLen[codelen];
      }
      n -= codelen;
      bitsLeft -= codelen;
      if (bitsLeft < 0) {
        break;
      }
      const r = Math.floor((maxcode - code) / ByteUtils.pow2(32 - codelen));
      if (r < 0 || r >= this.dicData.length) {
        throw new Error('invalid_huff_dict_index');
      }
      let slice = this.dicData[r];
      if (!this.dicFlags[r]) {
        // 压缩短语递归展开（memoize；占位防循环）
        const compressed = slice;
        this.dicData[r] = new Uint8Array(0);
        this.dicFlags[r] = true;
        slice = this.unpack(compressed);
        this.dicData[r] = slice;
      }
      out.appendBytes(slice, 0, slice.length);
    }
    return out.toUint8Array();
  }
}
