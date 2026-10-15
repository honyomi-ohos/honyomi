// Palm 数据库文件（.mobi/.azw/.prc）读取器：
// 78 字节头（name/type/creator/记录数）+ 记录表（每条 8 字节：偏移+属性）+ 记录数据。
// 口径对齐 KindleUnpack mobi_sectioner.py；纯逻辑，taskpool 可用。

import { ByteUtils } from './ByteUtils';

export class PalmDb {
  readonly bytes: Uint8Array;
  readonly palmName: string; // PDB name（头 32 字节）
  readonly ident: string; // type+creator，如 'BOOKMOBI' / 'TEXtREAd'
  readonly numRecords: number;
  private readonly offsets: number[] = [];

  constructor(bytes: Uint8Array) {
    if (bytes.length < 78) {
      throw new Error('invalid_palmdb');
    }
    this.bytes = bytes;
    this.palmName = ByteUtils.asciiAt(bytes, 0, 32);
    this.ident = ByteUtils.asciiAt(bytes, 60, 8);
    this.numRecords = ByteUtils.u16At(bytes, 76);
    if (78 + 8 * this.numRecords > bytes.length) {
      throw new Error('invalid_palmdb_record_table');
    }
    const offsets: number[] = [];
    for (let i = 0; i < this.numRecords; i++) {
      offsets.push(ByteUtils.u32At(bytes, 78 + 8 * i));
    }
    // 末尾哨兵：最后一条记录截至文件末尾
    offsets.push(bytes.length);
    this.offsets = offsets;
  }

  // 读取第 i 条记录（越界/坏表返回空数组）
  record(i: number): Uint8Array {
    if (i < 0 || i >= this.numRecords) {
      return new Uint8Array(0);
    }
    let start = this.offsets[i];
    let end = this.offsets[i + 1];
    if (start < 0 || start > this.bytes.length) {
      start = 0;
    }
    if (end > this.bytes.length || end < start) {
      end = this.bytes.length;
    }
    return this.bytes.subarray(start, end);
  }
}
