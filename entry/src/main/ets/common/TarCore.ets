// tar 解包核心（由 TarExtractor 的 taskpool 后台任务调用）：
// 512 字节头流式解析、POSIX ustar 与 GNU 兼容（含 GNU 长文件名 'L' 条目），
// pax 扩展头/链接/设备等条目跳过数据区，路径穿越条目整条拒绝。
// 二进制一律 fileIo 流式读取（显式 offset 定位 + 分块缓冲），禁止整文件读入。

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// 单个 tar 条目头解析结果
export class TarEntryHeader {
  name: string = '';
  size: number = 0;
  type: number = 0;
}

// tar 解包核心：一个实例对应一次解包
export class TarCore {
  // tar 头部块大小（字节）
  private static readonly BLOCK_SIZE: number = 512;
  // 数据搬运块大小（字节）
  private static readonly CHUNK_SIZE: number = 65536;
  // GNU 长文件名数据上限（防御异常 tar 导致超大分配）
  private static readonly LONGNAME_LIMIT: number = 1048576;
  // 条目数上限（防御压缩炸弹/损坏头导致的死循环）
  private static readonly MAX_ENTRIES: number = 200000;

  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: false });
  private readonly headerBuf: ArrayBuffer = new ArrayBuffer(TarCore.BLOCK_SIZE);
  private readonly chunkBuf: ArrayBuffer = new ArrayBuffer(TarCore.CHUNK_SIZE);
  private fd: number = -1;
  // 当前读取位置（绝对文件偏移；显式 offset 读取，跳过即推进游标）
  private pos: number = 0;
  private totalSize: number = 0;
  private outDir: string = '';
  // GNU 长文件名（'L' 条目数据区暂存，供下一真实条目使用）
  private longName: string = '';
  // pax 扩展头 path 记录（'x'/'g' 条目，优先级高于 GNU 长文件名）
  private paxName: string = '';
  private entryCount: number = 0;

  static extractTo(tarPath: string, outDir: string): void {
    const core = new TarCore();
    core.run(tarPath, outDir);
  }

  // ---------------- 解包主流程 ----------------

  private run(tarPath: string, outDir: string): void {
    this.outDir = outDir;
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(tarPath, fs.OpenMode.READ_ONLY);
    } catch (e) {
      throw new Error('无法读取压缩包');
    }
    this.fd = file.fd;
    try {
      this.totalSize = fs.statSync(file.fd).size;
      fs.mkdirSync(outDir, true);
      this.loopEntries();
    } finally {
      try {
        fs.closeSync(file);
      } catch (e) {
        // 关闭失败忽略
      }
    }
  }

  private loopEntries(): void {
    while (true) {
      const got = this.readFully(this.headerBuf, TarCore.BLOCK_SIZE);
      if (got === 0) {
        return;
      }
      if (got < TarCore.BLOCK_SIZE) {
        throw new Error('压缩包数据不完整');
      }
      if (this.isZeroBlock()) {
        return;
      }
      const header = this.parseHeader();
      if (header === null) {
        throw new Error('压缩包已损坏（头部校验失败）');
      }
      this.entryCount += 1;
      if (this.entryCount > TarCore.MAX_ENTRIES) {
        throw new Error('压缩包条目数超出上限');
      }
      // GNU 长文件名：数据区为下一真实条目的名字
      if (header.type === 76) {
        this.longName = this.decodeCStr(this.readDataBytes(header.size));
        this.skipPad(header.size);
        continue;
      }
      // pax 扩展头（'x' 局部 / 'g' 全局）：解析 path 记录供下一真实条目使用；
      // 'X'（SunOS 特殊）与其他扩展头忽略数据区
      if (header.type === 103 || header.type === 120) {
        const paxPath = this.parsePaxPath(this.readDataBytes(header.size));
        if (paxPath !== '') {
          this.paxName = paxPath;
        }
        this.skipPad(header.size);
        continue;
      }
      if (header.type === 75 || header.type === 88) {
        this.skipData(header.size);
        this.skipPad(header.size);
        continue;
      }
      // 条目名优先级：pax path 记录 > GNU 长文件名 > 头部 name（含 ustar prefix）
      const pendingPax = this.paxName;
      const pendingLong = this.longName;
      this.paxName = '';
      this.longName = '';
      const rawName = pendingPax !== '' ? pendingPax : (pendingLong !== '' ? pendingLong : header.name);
      const name = TarCore.sanitizeName(rawName);
      const isRegular = header.type === 0 || header.type === 48;
      const isDir = header.type === 53 || (isRegular && header.name.endsWith('/'));
      if (isDir) {
        if (name !== '') {
          fs.mkdirSync(`${this.outDir}/${name}`, true);
        }
        this.skipData(header.size);
      } else if (isRegular) {
        if (name === '') {
          this.skipData(header.size);
        } else {
          this.writeFile(name, header.size);
        }
      } else {
        // 硬/符号链接、设备、FIFO 等：跳过数据区
        this.skipData(header.size);
      }
      this.skipPad(header.size);
    }
  }

  // 常规文件条目：分块搬运数据区到输出文件
  private writeFile(name: string, size: number): void {
    const outPath = `${this.outDir}/${name}`;
    this.ensureParentDir(outPath);
    let out: fs.File | undefined = undefined;
    try {
      out = fs.openSync(outPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    } catch (e) {
      throw new Error('解压写入失败');
    }
    try {
      let done = 0;
      let outPos = 0;
      while (done < size) {
        const want = Math.min(size - done, TarCore.CHUNK_SIZE);
        const got = this.readFully(this.chunkBuf, want);
        if (got <= 0) {
          throw new Error('压缩包数据不完整');
        }
        fs.writeSync(out.fd, this.chunkBuf, { offset: outPos, length: got });
        outPos += got;
        done += got;
      }
    } finally {
      try {
        fs.closeSync(out);
      } catch (e) {
        // 关闭失败忽略
      }
    }
  }

  // ---------------- 头部解析 ----------------

  // 解析 512 字节头部；校验和不通过返回 null（视为损坏）
  private parseHeader(): TarEntryHeader | null {
    const b = new Uint8Array(this.headerBuf);
    // 头部求和校验：校验和字段（148..155）按空格 0x20 计
    let sum = 0;
    for (let i = 0; i < TarCore.BLOCK_SIZE; i++) {
      sum += (i >= 148 && i < 156) ? 32 : b[i];
    }
    const stored = TarCore.parseOctal(b, 148, 8);
    if (stored <= 0 || sum !== stored) {
      return null;
    }
    const header = new TarEntryHeader();
    header.name = this.cstring(b, 0, 100);
    header.size = TarCore.parseOctal(b, 124, 12);
    header.type = b[156];
    // 仅 POSIX ustar（magic "ustar\0"）有 prefix 字段；
    // GNU（magic "ustar "）该区域为时间戳等扩展字段，不能按 prefix 拼接
    if (b[257] === 117 && b[258] === 115 && b[259] === 116 && b[260] === 97 && b[261] === 114 && b[262] === 0) {
      const prefix = this.cstring(b, 345, 155);
      if (prefix !== '') {
        header.name = `${prefix}/${header.name}`;
      }
    }
    return header;
  }

  // 读取数据区为字节数组（GNU 长名/pax 头共用；超限防御）
  private readDataBytes(size: number): Uint8Array {
    if (size <= 0) {
      return new Uint8Array(0);
    }
    if (size > TarCore.LONGNAME_LIMIT) {
      throw new Error('压缩包已损坏（扩展头超限）');
    }
    const buf = new ArrayBuffer(size);
    const got = this.readFully(buf, size);
    if (got < size) {
      throw new Error('压缩包数据不完整');
    }
    return new Uint8Array(buf);
  }

  // pax 扩展头解析：字节层面按 "<len> <key>=<value>\n" 记录切分，提取 path 记录
  private parsePaxPath(bytes: Uint8Array): string {
    let idx = 0;
    while (idx < bytes.length) {
      // 记录头：十进制记录总长（含自身）+ 空格
      let sp = idx;
      while (sp < bytes.length && bytes[sp] !== 32) {
        sp += 1;
      }
      if (sp >= bytes.length) {
        break;
      }
      let recLen = 0;
      let valid = true;
      for (let i = idx; i < sp; i++) {
        const c = bytes[i];
        if (c < 48 || c > 57) {
          valid = false;
          break;
        }
        recLen = recLen * 10 + (c - 48);
      }
      if (!valid || recLen <= 0 || idx + recLen > bytes.length) {
        break;
      }
      const bodyEnd = idx + recLen;
      let eq = sp + 1;
      while (eq < bodyEnd && bytes[eq] !== 61) {
        eq += 1;
      }
      if (eq < bodyEnd) {
        // 键 "path"（p=112 a=97 t=116 h=104）
        const ks = sp + 1;
        if (eq - ks === 4 && bytes[ks] === 112 && bytes[ks + 1] === 97 &&
          bytes[ks + 2] === 116 && bytes[ks + 3] === 104) {
          let valEnd = bodyEnd;
          if (valEnd > eq + 1 && bytes[valEnd - 1] === 10) {
            valEnd -= 1;
          }
          return this.decoder.decodeToString(bytes.subarray(eq + 1, valEnd));
        }
      }
      idx += recLen;
    }
    return '';
  }

  // 字节按 NUL 截断解码（GNU 长文件名数据区）
  private decodeCStr(bytes: Uint8Array): string {
    let end = 0;
    while (end < bytes.length && bytes[end] !== 0) {
      end += 1;
    }
    return this.decoder.decodeToString(bytes.subarray(0, end));
  }

  // ---------------- 底层读取 ----------------

  // 从当前游标起读满 len 字节到 buf 起始处；返回实际读取数（0 = EOF）
  private readFully(buf: ArrayBuffer, len: number): number {
    let done = 0;
    while (done < len) {
      const got: number = fs.readSync(this.fd, buf, { offset: this.pos, length: len - done });
      if (got <= 0) {
        return done;
      }
      done += got;
      this.pos += got;
    }
    return done;
  }

  // 跳过数据区（显式 offset 读取下推进游标即可）
  private skipData(size: number): void {
    this.pos += size;
    if (this.pos > this.totalSize) {
      throw new Error('压缩包数据不完整');
    }
  }

  // tar 条目数据按 512 字节对齐，跳过尾部填充
  private skipPad(size: number): void {
    const pad = (TarCore.BLOCK_SIZE - (size % TarCore.BLOCK_SIZE)) % TarCore.BLOCK_SIZE;
    if (pad > 0) {
      this.skipData(pad);
    }
  }

  private isZeroBlock(): boolean {
    const b = new Uint8Array(this.headerBuf);
    for (let i = 0; i < b.length; i++) {
      if (b[i] !== 0) {
        return false;
      }
    }
    return true;
  }

  private ensureParentDir(path: string): void {
    const idx = path.lastIndexOf('/');
    if (idx <= 0) {
      return;
    }
    try {
      fs.mkdirSync(path.substring(0, idx), true);
    } catch (e) {
      // 已存在等情况忽略，后续 openSync 失败会给出明确错误
    }
  }

  // 字节区按 NUL 截断的 UTF-8 字符串
  private cstring(b: Uint8Array, off: number, max: number): string {
    let end = off;
    const limit = Math.min(off + max, b.length);
    while (end < limit && b[end] !== 0) {
      end += 1;
    }
    return this.decoder.decodeToString(b.subarray(off, end));
  }

  // 八进制字段解析（GNU base-256 编码兼容；容忍前导空格/NUL）
  private static parseOctal(b: Uint8Array, off: number, len: number): number {
    if ((b[off] & 0x80) !== 0) {
      let v = b[off] & 0x7F;
      for (let i = 1; i < len; i++) {
        v = v * 256 + b[off + i];
      }
      return v;
    }
    let v = 0;
    let started = false;
    for (let i = 0; i < len; i++) {
      const c = b[off + i];
      if (c === 0 || c === 32) {
        if (started) {
          break;
        }
        continue;
      }
      if (c < 48 || c > 55) {
        break;
      }
      started = true;
      v = v * 8 + (c - 48);
    }
    return v;
  }

  // 条目名净化：去前导 '/'，剔除空段与 '.'，含 '..' 的路径穿越条目整条拒绝
  private static sanitizeName(name: string): string {
    let n = name;
    while (n.startsWith('/')) {
      n = n.substring(1);
    }
    const segs = n.split('/');
    const kept: string[] = [];
    for (const seg of segs) {
      if (seg === '' || seg === '.') {
        continue;
      }
      if (seg === '..') {
        return '';
      }
      kept.push(seg);
    }
    return kept.join('/');
  }
}
