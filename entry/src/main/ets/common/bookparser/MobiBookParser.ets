// MOBI/AZW/AZW3/PRC 书籍解析：PalmDB → 记录解压(PalmDOC/HUFF-CDIC) → rawML →
// MOBI6(<mbp:pagebreak> 切分) 或 KF8(FDST+skeleton/fragment 重组) → 章节 HTML + 图片落盘。
// 口径对齐 KindleUnpack（kindleunpack.py / mobi_header.py / mobi_k8proc.py / mobi_html.py）；
// 纯逻辑无 UI 依赖，taskpool 可用。

import { ByteBuilder, ByteUtils, BookFileIo, BookTextCodec } from './ByteUtils';
import { PalmDb } from './PalmDb';
import { PalmdocDecoder, HuffCdicDecoder } from './MobiCodec';
import { IndxParser, IndxTable } from './IndxParser';

// 解析结果：章节 HTML 已重写为 file:// 图片绝对路径；封面已落盘
export class MobiBookResult {
  title: string = '';
  author: string = '';
  chapters: string[] = [];
  chapterNames: string[] = [];
  coverPath: string = '';
}

// MOBI 头信息（记录 0 或组合文件 KF8 头记录）
class MobiHeaderInfo {
  start: number = 0;
  records: number = 0;
  compression: number = 1;
  crypto: number = 0;
  codepage: number = 1252;
  version: number = 0;
  headerLength: number = 0;
  title: string = '';
  huffOff: number = -1;
  huffNum: number = 0;
  firstResource: number = 0;
  exth: Map<number, Uint8Array> = new Map();
  multibyte: number = 0;
  trailers: number = 0;
  skelIdx: number = -1;
  fragIdx: number = -1;
  fdst: number = -1;
}

// 记录解压器统一包装（passthrough / palmdoc / huff）
class MobiRecordDecoder {
  private huff: HuffCdicDecoder | null = null;

  constructor(compression: number, huff: HuffCdicDecoder | null) {
    this.huff = huff;
  }

  decode(data: Uint8Array): Uint8Array {
    if (this.huff !== null) {
      return this.huff.unpack(data);
    }
    return PalmdocDecoder.decode(data);
  }
}

export class MobiBookParser {
  // 主入口：bytes = 整本书文件；cacheDir = 本书缓存目录（图片写入 cacheDir/images）
  static parse(bytes: Uint8Array, cacheDir: string): MobiBookResult {
    const db = new PalmDb(bytes);
    if (db.ident !== 'BOOKMOBI' && db.ident !== 'TEXtREAd') {
      throw new Error('unsupported_format');
    }
    let hdr = MobiBookParser.parseHeader(db, 0);
    // 组合文件（MOBI6+KF8）：定位 BOUNDARY 记录，优先 KF8 部分
    if (!MobiBookParser.isK8(hdr)) {
      const boundary = MobiBookParser.findBoundary(db);
      if (boundary > 0) {
        hdr = MobiBookParser.parseHeader(db, boundary + 1);
      }
    }
    if (hdr.crypto !== 0) {
      throw new Error('encrypted_book');
    }
    const firstText = db.record(hdr.start + 1);
    if (ByteUtils.startsWithAscii(firstText, 0, '%MOP')) {
      throw new Error('print_replica_unsupported');
    }
    const decoder = MobiBookParser.buildDecoder(db, hdr);
    const rawMl = MobiBookParser.getRawMl(db, hdr, decoder);
    // 图片落盘（槽位序号对齐记录区间，非图片记录占空槽）
    const imagesDir = `${cacheDir}/images`;
    BookFileIo.ensureDir(imagesDir);
    const slots = MobiBookParser.extractImages(db, hdr, imagesDir);
    // 组装结果
    const result = new MobiBookResult();
    result.title = MobiBookParser.resolveTitle(db, hdr);
    result.author = MobiBookParser.resolveAuthor(hdr);
    result.coverPath = MobiBookParser.pickCover(hdr, slots);
    if (MobiBookParser.isK8(hdr)) {
      MobiBookParser.buildKf8Chapters(db, hdr, rawMl, slots, result);
    } else {
      MobiBookParser.buildMobi6Chapters(hdr, rawMl, slots, result);
    }
    if (result.chapters.length === 0) {
      throw new Error('empty_book');
    }
    return result;
  }

  // ---------------- 头解析 ----------------

  private static isK8(hdr: MobiHeaderInfo): boolean {
    return hdr.start !== 0 || hdr.version === 8;
  }

  // 8 字节 'BOUNDARY' 记录 → 组合文件分界
  private static findBoundary(db: PalmDb): number {
    for (let i = 1; i < db.numRecords; i++) {
      const rec = db.record(i);
      if (rec.length === 8 && ByteUtils.startsWithAscii(rec, 0, 'BOUNDARY')) {
        return i;
      }
    }
    return -1;
  }

  private static parseHeader(db: PalmDb, start: number): MobiHeaderInfo {
    const rec = db.record(start);
    const hdr = new MobiHeaderInfo();
    hdr.start = start;
    if (rec.length < 20) {
      throw new Error('invalid_mobi_header');
    }
    const hasMobi = ByteUtils.startsWithAscii(rec, 16, 'MOBI');
    if (!hasMobi && db.ident !== 'TEXtREAd') {
      throw new Error('invalid_mobi_header');
    }
    hdr.records = ByteUtils.u16At(rec, 8);
    hdr.compression = ByteUtils.u16At(rec, 0);
    // TEXtREAd：纯 PalmDOC，无 MOBI 头
    if (!hasMobi) {
      hdr.firstResource = start + hdr.records + 1;
      return hdr;
    }
    if (rec.length < 0x108) {
      throw new Error('invalid_mobi_header');
    }
    hdr.crypto = ByteUtils.u16At(rec, 0xC);
    hdr.headerLength = ByteUtils.u32At(rec, 0x14);
    hdr.codepage = ByteUtils.u32At(rec, 0x1C);
    hdr.version = ByteUtils.u32At(rec, 0x24);
    if (hdr.compression === 0x4448) {
      hdr.huffOff = ByteUtils.u32At(rec, 0x70) + start;
      hdr.huffNum = ByteUtils.u32At(rec, 0x74);
    }
    // 书名
    const toff = ByteUtils.u32At(rec, 0x54);
    const tlen = ByteUtils.u32At(rec, 0x58);
    if (toff + tlen > 0 && toff + tlen <= rec.length) {
      hdr.title = BookTextCodec.decodeMobi(rec.subarray(toff, toff + tlen), hdr.codepage);
    }
    // EXTH
    const exthFlag = ByteUtils.u32At(rec, 0x80);
    if ((exthFlag & 0x40) !== 0) {
      MobiBookParser.parseExth(rec, hdr);
    }
    // 资源起始记录
    const firstRes = ByteUtils.u32At(rec, 0x6C);
    hdr.firstResource = firstRes !== 0xFFFFFFFF ? firstRes + start : start + hdr.records + 1;
    // 尾随数据标志（记录级 trim 依据）
    if (hdr.headerLength >= 0xE4 && hdr.version >= 5) {
      const flags = ByteUtils.u16At(rec, 0xF2);
      hdr.multibyte = flags & 1;
      let f = flags;
      while (f > 1) {
        if ((f & 2) !== 0) {
          hdr.trailers += 1;
        }
        f = f >> 1;
      }
    }
    // KF8 索引（需头长 +16 ≥ 0xF8）
    if (hdr.headerLength + 16 >= 0xF8) {
      if (MobiBookParser.isK8(hdr)) {
        const skel = ByteUtils.u32At(rec, 0xFC);
        const frag = ByteUtils.u32At(rec, 0xF8);
        if (skel !== 0xFFFFFFFF) {
          hdr.skelIdx = skel + start;
        }
        if (frag !== 0xFFFFFFFF) {
          hdr.fragIdx = frag + start;
        }
        const fdst = ByteUtils.u32At(rec, 0xC0);
        const fdstCnt = ByteUtils.u32At(rec, 0xC4);
        if (fdstCnt > 1 && fdst !== 0xFFFFFFFF) {
          hdr.fdst = fdst + start;
        }
      }
    }
    return hdr;
  }

  private static parseExth(rec: Uint8Array, hdr: MobiHeaderInfo): void {
    const off = hdr.headerLength + 16;
    if (off + 12 > rec.length || !ByteUtils.startsWithAscii(rec, off, 'EXTH')) {
      return;
    }
    const count = ByteUtils.u32At(rec, off + 8);
    let pos = off + 12;
    for (let i = 0; i < count; i++) {
      if (pos + 8 > rec.length) {
        break;
      }
      const id = ByteUtils.u32At(rec, pos);
      const size = ByteUtils.u32At(rec, pos + 4);
      if (size < 8 || pos + size > rec.length) {
        break;
      }
      if (!hdr.exth.has(id)) {
        hdr.exth.set(id, rec.subarray(pos + 8, pos + size));
      }
      pos += size;
    }
  }

  // ---------------- 记录解码 ----------------

  private static buildDecoder(db: PalmDb, hdr: MobiHeaderInfo): MobiRecordDecoder {
    if (hdr.compression === 1) {
      return new MobiRecordDecoder(1, null);
    }
    if (hdr.compression === 2) {
      return new MobiRecordDecoder(2, null);
    }
    if (hdr.compression === 0x4448) {
      const huff = new HuffCdicDecoder();
      const huffRec = db.record(hdr.huffOff);
      huff.loadHuff(huffRec);
      for (let i = 1; i < hdr.huffNum; i++) {
        const cdicRec = db.record(hdr.huffOff + i);
        if (cdicRec.length === 0) {
          break;
        }
        huff.loadCdic(cdicRec);
      }
      return new MobiRecordDecoder(0x4448, huff);
    }
    throw new Error('unsupported_compression');
  }

  // 尾随条目长度（变宽，末 4 字节）
  private static sizeOfTrailingEntry(data: Uint8Array): number {
    let num = 0;
    const end = data.length;
    for (let i = Math.max(0, end - 4); i < end; i++) {
      const v = data[i];
      if ((v & 0x80) !== 0) {
        num = 0;
      }
      num = (num << 7) | (v & 0x7F);
    }
    return num;
  }

  private static trimTrailing(hdr: MobiHeaderInfo, data: Uint8Array): Uint8Array {
    let out = data;
    for (let i = 0; i < hdr.trailers; i++) {
      const num = MobiBookParser.sizeOfTrailingEntry(out);
      if (num > 0 && num <= out.length) {
        out = out.subarray(0, out.length - num);
      }
    }
    if (hdr.multibyte !== 0 && out.length > 0) {
      const num = (out[out.length - 1] & 3) + 1;
      if (num <= out.length) {
        out = out.subarray(0, out.length - num);
      }
    }
    return out;
  }

  private static getRawMl(db: PalmDb, hdr: MobiHeaderInfo, decoder: MobiRecordDecoder): Uint8Array {
    const builder = new ByteBuilder(1024 * 64);
    const count = Math.min(hdr.records, db.numRecords - hdr.start - 1);
    const trimNeeded = db.ident === 'BOOKMOBI';
    for (let i = 1; i <= count; i++) {
      let data = db.record(hdr.start + i);
      if (trimNeeded && data.length > 0) {
        data = MobiBookParser.trimTrailing(hdr, data);
      }
      const decoded = decoder.decode(data);
      builder.appendBytes(decoded, 0, decoded.length);
    }
    return builder.toUint8Array();
  }

  // ---------------- 图片 ----------------

  private static sniffImage(data: Uint8Array): string {
    if (data.length < 8) {
      return '';
    }
    if (data[0] === 0xFF && data[1] === 0xD8 && data[2] === 0xFF) {
      return 'jpg';
    }
    if (data[0] === 0x89 && data[1] === 0x50 && data[2] === 0x4E && data[3] === 0x47) {
      return 'png';
    }
    if (ByteUtils.startsWithAscii(data, 0, 'GIF8')) {
      return 'gif';
    }
    if (data[0] === 0x42 && data[1] === 0x4D) {
      return 'bmp';
    }
    return '';
  }

  // HD 容器记录（'CONT' 开头）：提取内部最大 JPEG span
  private static extractContJpeg(data: Uint8Array): Uint8Array | null {
    let soi = -1;
    for (let i = 0; i + 1 < data.length; i++) {
      if (data[i] === 0xFF && data[i + 1] === 0xD8) {
        soi = i;
        break;
      }
    }
    if (soi < 0) {
      return null;
    }
    let eoi = -1;
    for (let i = data.length - 2; i > soi; i--) {
      if (data[i] === 0xFF && data[i + 1] === 0xD9) {
        eoi = i + 2;
        break;
      }
    }
    if (eoi < 0 || eoi - soi < 64) {
      return null;
    }
    return data.subarray(soi, eoi);
  }

  // 逐记录提取图片：返回槽位数组（下标 = 序号-1），非图片记录为 null
  private static extractImages(db: PalmDb, hdr: MobiHeaderInfo, imagesDir: string): Array<string | null> {
    const slots: Array<string | null> = [];
    for (let i = hdr.firstResource; i < db.numRecords; i++) {
      const data = db.record(i);
      let written: string | null = null;
      const ext = MobiBookParser.sniffImage(data);
      if (ext !== '') {
        const name = `IMG_${slots.length + 1}.${ext}`;
        const path = `${imagesDir}/${name}`;
        BookFileIo.writeBytes(path, data);
        written = path;
      } else if (ByteUtils.startsWithAscii(data, 0, 'CONT')) {
        const jpeg = MobiBookParser.extractContJpeg(data);
        if (jpeg !== null) {
          const name = `IMG_${slots.length + 1}.jpg`;
          const path = `${imagesDir}/${name}`;
          BookFileIo.writeBytes(path, jpeg);
          written = path;
        }
      }
      slots.push(written);
    }
    return slots;
  }

  // EXTH 取 u32
  private static exthU32(hdr: MobiHeaderInfo, id: number, fallback: number): number {
    const content = hdr.exth.get(id);
    if (content === undefined || content.length < 4) {
      return fallback;
    }
    return ByteUtils.u32At(content, 0);
  }

  private static pickCover(hdr: MobiHeaderInfo, slots: Array<string | null>): string {
    const coverOffset = MobiBookParser.exthU32(hdr, 201, -1);
    if (coverOffset >= 0 && coverOffset < slots.length && slots[coverOffset] !== null) {
      return slots[coverOffset] as string;
    }
    const thumbOffset = MobiBookParser.exthU32(hdr, 202, -1);
    if (thumbOffset >= 0 && thumbOffset < slots.length && slots[thumbOffset] !== null) {
      return slots[thumbOffset] as string;
    }
    for (const slot of slots) {
      if (slot !== null) {
        return slot;
      }
    }
    return '';
  }

  private static resolveTitle(db: PalmDb, hdr: MobiHeaderInfo): string {
    const updated = hdr.exth.get(503);
    if (updated !== undefined && updated.length > 0) {
      const decoded = BookTextCodec.decodeMobi(updated, hdr.codepage).trim();
      if (decoded !== '') {
        return decoded;
      }
    }
    if (hdr.title.trim() !== '') {
      return hdr.title.trim();
    }
    return db.palmName.trim();
  }

  private static resolveAuthor(hdr: MobiHeaderInfo): string {
    const author = hdr.exth.get(100);
    if (author !== undefined && author.length > 0) {
      return BookTextCodec.decodeMobi(author, hdr.codepage).trim();
    }
    return '';
  }

  // ---------------- 章节构建 ----------------

  // KF8：FDST 分流 → skeleton/fragment 线性重组 → 每 skeleton 一章
  private static buildKf8Chapters(db: PalmDb, hdr: MobiHeaderInfo, rawMl: Uint8Array,
    slots: Array<string | null>, result: MobiBookResult): void {
    const flow0 = MobiBookParser.getFlow0(db, hdr, rawMl);
    const skelTable = hdr.skelIdx >= 0 ? IndxParser.getIndexData(db, hdr.skelIdx) : null;
    const fragTable = hdr.fragIdx >= 0 ? IndxParser.getIndexData(db, hdr.fragIdx) : null;
    const parts = MobiBookParser.assembleParts(flow0, skelTable, fragTable);
    for (const part of parts) {
      const html = BookTextCodec.decodeMobi(part, hdr.codepage);
      const rewritten = MobiBookParser.rewriteKf8Images(html, slots);
      result.chapters.push(rewritten);
      result.chapterNames.push(MobiBookParser.extractTitleTag(rewritten, result.chapters.length));
    }
  }

  // FDST 表 → flow0（正文流）；无 FDST 时 flow0 = 整个 rawML
  private static getFlow0(db: PalmDb, hdr: MobiHeaderInfo, rawMl: Uint8Array): Uint8Array {
    if (hdr.fdst < 0 || hdr.fdst >= db.numRecords) {
      return rawMl;
    }
    const fdstRec = db.record(hdr.fdst);
    if (fdstRec.length < 16 || !ByteUtils.startsWithAscii(fdstRec, 0, 'FDST')) {
      return rawMl;
    }
    const numSections = ByteUtils.u32At(fdstRec, 8);
    if (numSections < 1) {
      return rawMl;
    }
    const starts: number[] = [];
    for (let i = 0; i < numSections; i++) {
      const at = 12 + 8 * i;
      if (at + 4 > fdstRec.length) {
        break;
      }
      starts.push(ByteUtils.u32At(fdstRec, at));
    }
    starts.push(rawMl.length);
    if (starts.length < 2 || starts[0] > rawMl.length) {
      return rawMl;
    }
    const end = Math.min(starts[1], rawMl.length);
    return rawMl.subarray(starts[0], end);
  }

  // skeleton/fragment 重组（对齐 mobi_k8proc.buildParts，插入点单调故线性拼装）
  private static assembleParts(flow0: Uint8Array, skelTable: IndxTable | null,
    fragTable: IndxTable | null): Uint8Array[] {
    if (skelTable === null || skelTable.entries.length === 0) {
      return [flow0];
    }
    const parts: Uint8Array[] = [];
    let fragPtr = 0;
    for (const skel of skelTable.entries) {
      const fragcnt = IndxParser.tagValue(skel.tagMap, 1, 0, 0);
      const skelpos = IndxParser.tagValue(skel.tagMap, 6, 0, 0);
      const skellen = IndxParser.tagValue(skel.tagMap, 6, 1, 0);
      if (skelpos < 0 || skelpos > flow0.length) {
        continue;
      }
      const skelEnd = Math.min(skelpos + skellen, flow0.length);
      let baseptr = skelEnd;
      const builder = new ByteBuilder(1024 * 16);
      // 线性拼装：骨架段片段与碎片片段交替输出（碎片按最终文档坐标递增插入）
      let prevRel = 0;
      builder.reset();
      for (let i = 0; i < fragcnt; i++) {
        if (fragTable === null || fragPtr >= fragTable.entries.length) {
          break;
        }
        const frag = fragTable.entries[fragPtr];
        fragPtr += 1;
        const insertpos = MobiBookParser.parseIntSafe(BookTextCodec.decodeUtf8(frag.textBytes), -1);
        const startpos = IndxParser.tagValue(frag.tagMap, 6, 0, -1);
        const length = IndxParser.tagValue(frag.tagMap, 6, 1, 0);
        if (insertpos < 0 || startpos < 0 || length <= 0) {
          continue;
        }
        let rel = insertpos - skelpos;
        if (rel < prevRel) {
          rel = prevRel;
        }
        if (rel > skellen) {
          rel = skellen;
        }
        const segEnd = skelpos + rel;
        if (segEnd > prevRel + skelpos) {
          builder.appendBytes(flow0, prevRel + skelpos, segEnd - (prevRel + skelpos));
        }
        const fragEnd = Math.min(baseptr + length, flow0.length);
        if (baseptr < fragEnd) {
          builder.appendBytes(flow0, baseptr, fragEnd - baseptr);
          baseptr = fragEnd;
        }
        prevRel = rel;
      }
      const tailStart = skelpos + prevRel;
      if (tailStart < skelEnd) {
        builder.appendBytes(flow0, tailStart, skelEnd - tailStart);
      }
      parts.push(builder.toUint8Array());
    }
    if (parts.length === 0) {
      return [flow0];
    }
    return parts;
  }

  // kindle:embed:XXXX（base32）→ file:// 绝对路径；缺槽位替换为空
  private static rewriteKf8Images(html: string, slots: Array<string | null>): string {
    return html.replace(/kindle:embed:([0-9A-Va-v]+)(\?[^"'\s)]*)?/g, (match: string, num: string): string => {
      const seq = MobiBookParser.fromBase32(num);
      if (seq >= 1 && seq <= slots.length && slots[seq - 1] !== null) {
        return `file://${slots[seq - 1]}`;
      }
      return '';
    });
  }

  // MOBI6：<mbp:pagebreak> 切分 + recindex 重写
  private static buildMobi6Chapters(hdr: MobiHeaderInfo, rawMl: Uint8Array,
    slots: Array<string | null>, result: MobiBookResult): void {
    const text = BookTextCodec.decodeMobi(rawMl, hdr.codepage);
    const pieces = text.split(/<mbp:pagebreak[^>]*\/?>/i);
    for (const piece of pieces) {
      const trimmed = piece.trim();
      if (trimmed === '') {
        continue;
      }
      const rewritten = MobiBookParser.rewriteMobi6Images(trimmed, slots);
      result.chapters.push(rewritten);
      result.chapterNames.push(MobiBookParser.extractHeading(rewritten, result.chapters.length));
    }
  }

  // recindex="N"（十进制）→ src="file://绝对路径"
  private static rewriteMobi6Images(html: string, slots: Array<string | null>): string {
    return html.replace(/recindex\s*=\s*["']?(\d+)["']?/gi, (match: string, num: string): string => {
      const seq = MobiBookParser.parseIntSafe(num, -1);
      if (seq >= 1 && seq <= slots.length && slots[seq - 1] !== null) {
        return `src="file://${slots[seq - 1]}"`;
      }
      return match;
    });
  }

  // ---------------- 通用工具 ----------------

  // base32（0-9 A-V，右对齐 32 幂）→ 数值，对齐 KindleUnpack fromBase32
  private static fromBase32(s: string): number {
    const scaleLst: number[] = [1, 32, 1024, 32768, 1048576, 33554432, 1073741824];
    let value = 0;
    let j = 0;
    let scale = 0;
    for (let i = s.length - 1; i >= 0; i--) {
      const c = s.charCodeAt(i);
      let v: number;
      if (c >= 0x30 && c <= 0x39) {
        v = c - 0x30;
      } else if (c >= 0x41 && c <= 0x56) {
        v = c - 0x41 + 10;
      } else if (c >= 0x61 && c <= 0x76) {
        v = c - 0x61 + 10;
      } else {
        v = 0;
      }
      if (j < scaleLst.length) {
        scale = scaleLst[j];
      } else {
        scale = scale * 32;
      }
      j += 1;
      if (v !== 0) {
        value += v * scale;
      }
    }
    return value;
  }

  private static parseIntSafe(s: string, fallback: number): number {
    const n = Number.parseInt(s.trim(), 10);
    return Number.isNaN(n) ? fallback : n;
  }

  // <title> 提取（KF8 章节名）
  private static extractTitleTag(html: string, index: number): string {
    const m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
    if (m !== null) {
      const name = MobiBookParser.cleanChapterName(m[1]);
      if (name !== '') {
        return name;
      }
    }
    return MobiBookParser.extractHeading(html, index);
  }

  // 首个 h1/h2/h3 提取（MOBI6 章节名启发式）
  private static extractHeading(html: string, index: number): string {
    const m = /<h[123][^>]*>([\s\S]*?)<\/h[123]>/i.exec(html);
    if (m !== null) {
      const name = MobiBookParser.cleanChapterName(m[1]);
      if (name !== '') {
        return name;
      }
    }
    return `${index}`;
  }

  private static cleanChapterName(raw: string): string {
    let name = raw.replace(/<[^>]+>/g, ' ');
    name = name.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&#39;/g, '\'').replace(/&nbsp;/g, ' ');
    name = name.replace(/\s+/g, ' ').trim();
    if (name.length > 80) {
      name = name.substring(0, 80);
    }
    return name;
  }
}
