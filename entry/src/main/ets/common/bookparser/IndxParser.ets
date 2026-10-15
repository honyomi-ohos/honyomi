// MOBI INDX 索引解析（skeleton/fragment/CTOC/TAGX）。
// 口径对齐 KindleUnpack mobi_index.py；纯逻辑，taskpool 可用。

import { ByteUtils } from './ByteUtils';
import { PalmDb } from './PalmDb';

// 单条索引项：text（原始字节）+ tag 值表
export class IndxEntry {
  textBytes: Uint8Array = new Uint8Array(0);
  tagMap: Map<number, number[]> = new Map();
}

// 一次完整索引（主 INDX 节 + 附属 INDX 节 + CTOC 节）的解析结果
export class IndxTable {
  entries: IndxEntry[] = [];
  ctoc: Map<number, Uint8Array> = new Map();  // ctoc 起始偏移 -> 原始字节
}

// INDX 头字段
export class IndxHeader {
  len: number = 0;
  start: number = 0;
  count: number = 0;
  code: number = 0;
  nctoc: number = 0;
  ordt2: number[] | null = null;  // ORDT2 双字节映射表（text 字节经此映射）
}

// TAGX 标签定义（4 字节：tag / valuesPerEntry / mask / endFlag）
export class TagxTag {
  tag: number = 0;
  valuesPerEntry: number = 0;
  mask: number = 0;
  endFlag: number = 0;
}

export class TagxSection {
  controlByteCount: number = 0;
  tags: TagxTag[] = [];
}

// 变宽整数读取结果（值 + 结束偏移）
export class VarWidthValue {
  value: number = 0;
  next: number = 0;
}

// 待解码标签（getTagMap 中间态）
class PendingTag {
  tag: number = 0;
  valueCount: number = -1;   // -1 = 未定（走 valueBytes 分支）
  valueBytes: number = -1;
  valuesPerEntry: number = 0;
}

export class IndxParser {
  // 解析一条完整索引：主节 idx、附属节 idx+1..、CTOC 节 idx+count+1..
  static getIndexData(db: PalmDb, idx: number): IndxTable | null {
    if (idx < 0 || idx >= db.numRecords) {
      return null;
    }
    const table = new IndxTable();
    const data = db.record(idx);
    const hdr = IndxParser.parseIndxHeader(data);
    if (hdr === null) {
      return null;
    }
    const indexCount = hdr.count;
    // CTOC 附属节（可能多节，偏移基数逐节 +0x10000）
    let recOff = 0;
    for (let j = 0; j < hdr.nctoc; j++) {
      const sec = idx + indexCount + 1 + j;
      if (sec < 0 || sec >= db.numRecords) {
        break;
      }
      const ctoc = IndxParser.readCtoc(db.record(sec));
      ctoc.forEach((value: Uint8Array, key: number): void => {
        table.ctoc.set(key + recOff, value);
      });
      recOff += 0x10000;
    }
    // TAGX 标签表
    const tagSection = IndxParser.readTagSection(hdr.len, data);
    const controlByteCount = tagSection.controlByteCount;
    const tagTable = tagSection.tags;
    // 附属 INDX 节逐条解析
    const last = Math.min(idx + indexCount, db.numRecords - 1);
    for (let i = idx + 1; i <= last; i++) {
      const secData = db.record(i);
      const hdr2 = IndxParser.parseIndxHeader(secData);
      if (hdr2 === null) {
        continue;
      }
      const idxtPos = hdr2.start;
      const entryCount = hdr2.count;
      const positions: number[] = [];
      for (let j = 0; j < entryCount; j++) {
        const at = idxtPos + 4 + 2 * j;
        if (at + 2 > secData.length) {
          positions.push(idxtPos);
        } else {
          positions.push(ByteUtils.u16At(secData, at));
        }
      }
      // 末条以 IDXT 起点为界
      positions.push(idxtPos);
      for (let j = 0; j < entryCount; j++) {
        const startPos = positions[j];
        const endPos = positions[j + 1];
        if (startPos >= secData.length || endPos > secData.length || startPos >= endPos) {
          continue;
        }
        const textLength = secData[startPos];
        const textEnd = Math.min(startPos + 1 + textLength, secData.length);
        let text = secData.subarray(startPos + 1, textEnd);
        if (hdr.ordt2 !== null) {
          text = IndxParser.mapOrdt2(hdr.ordt2, text);
        }
        const entry = new IndxEntry();
        entry.textBytes = text;
        entry.tagMap = IndxParser.getTagMap(controlByteCount, tagTable, secData, startPos + 1 + textLength, endPos);
        table.entries.push(entry);
      }
    }
    return table;
  }

  // 读取 tagMap 指定 tag 的第 index 个值（缺省 fallback）
  static tagValue(tagMap: Map<number, number[]>, tag: number, index: number, fallback: number): number {
    const values = tagMap.get(tag);
    if (values === undefined || index >= values.length) {
      return fallback;
    }
    return values[index];
  }

  // ---------------- 内部实现 ----------------

  private static parseIndxHeader(data: Uint8Array): IndxHeader | null {
    if (data.length < 0xB8 || !ByteUtils.startsWithAscii(data, 0, 'INDX')) {
      return null;
    }
    const hdr = new IndxHeader();
    hdr.len = ByteUtils.u32At(data, 4);
    hdr.start = ByteUtils.u32At(data, 20);
    hdr.count = ByteUtils.u32At(data, 24);
    hdr.code = ByteUtils.u32At(data, 28);
    hdr.nctoc = ByteUtils.u32At(data, 52);
    // ORDT 表（罕见 ESP 样书：text 字节需经 ORDT2 映射）
    const oentries = ByteUtils.u32At(data, 0xAC);
    const op2 = ByteUtils.u32At(data, 0xB4);
    if (hdr.code === 0xFDEA && oentries > 0 && op2 + 4 + 2 * oentries <= data.length) {
      const ordt2: number[] = [];
      for (let i = 0; i < oentries; i++) {
        ordt2.push(ByteUtils.u16At(data, op2 + 4 + 2 * i));
      }
      hdr.ordt2 = ordt2;
    }
    return hdr;
  }

  // ORDT2 映射：逐字节查表（值截断为字节宽）
  private static mapOrdt2(ordt2: number[], text: Uint8Array): Uint8Array {
    const out = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) {
      const mapped = ordt2[text[i]];
      out[i] = mapped !== undefined ? mapped & 0xFF : text[i];
    }
    return out;
  }

  // CTOC 节：变宽长度前缀 + 名称字节的连续块表
  private static readCtoc(txtdata: Uint8Array): Map<number, Uint8Array> {
    const out = new Map<number, Uint8Array>();
    let offset = 0;
    while (offset < txtdata.length) {
      if (txtdata[offset] === 0) {
        break;
      }
      const idxOffs = offset;
      const vwi = IndxParser.variableWidthValue(txtdata, offset);
      if (vwi.value <= 0 || vwi.next + vwi.value > txtdata.length) {
        break;
      }
      out.set(idxOffs, txtdata.subarray(vwi.next, vwi.next + vwi.value));
      offset = vwi.next + vwi.value;
    }
    return out;
  }

  private static variableWidthValue(data: Uint8Array, offset: number): VarWidthValue {
    const result = new VarWidthValue();
    let value = 0;
    let consumed = 0;
    let finished = false;
    while (!finished && offset + consumed < data.length) {
      const v = data[offset + consumed];
      consumed += 1;
      if ((v & 0x80) !== 0) {
        finished = true;
      }
      value = (value << 7) | (v & 0x7F);
    }
    result.value = value;
    result.next = offset + consumed;
    return result;
  }

  private static readTagSection(start: number, data: Uint8Array): TagxSection {
    const section = new TagxSection();
    if (start < 0 || start + 12 > data.length) {
      return section;
    }
    if (!ByteUtils.startsWithAscii(data, start, 'TAGX')) {
      return section;
    }
    const firstEntryOffset = ByteUtils.u32At(data, start + 4);
    section.controlByteCount = ByteUtils.u32At(data, start + 8);
    for (let i = 12; i < firstEntryOffset; i += 4) {
      const at = start + i;
      if (at + 4 > data.length) {
        break;
      }
      const tag = new TagxTag();
      tag.tag = data[at];
      tag.valuesPerEntry = data[at + 1];
      tag.mask = data[at + 2];
      tag.endFlag = data[at + 3];
      section.tags.push(tag);
    }
    return section;
  }

  private static countSetBits(value: number): number {
    let count = 0;
    let v = value;
    for (let i = 0; i < 8; i++) {
      if ((v & 0x01) === 0x01) {
        count += 1;
      }
      v = v >> 1;
    }
    return count;
  }

  // 索引项 tag 值解码：控制字节位标志 → 变宽值序列
  private static getTagMap(controlByteCount: number, tagTable: TagxTag[], entryData: Uint8Array,
    startPos: number, endPos: number): Map<number, number[]> {
    const pending: PendingTag[] = [];
    let controlByteIndex = 0;
    let dataStart = startPos + controlByteCount;
    for (const tagEntry of tagTable) {
      if ((tagEntry.endFlag & 0x01) !== 0) {
        controlByteIndex += 1;
        continue;
      }
      if (startPos + controlByteIndex >= entryData.length) {
        break;
      }
      const cbyte = entryData[startPos + controlByteIndex];
      let value = cbyte & tagEntry.mask;
      if (value !== 0) {
        const pendingTag = new PendingTag();
        pendingTag.tag = tagEntry.tag;
        pendingTag.valuesPerEntry = tagEntry.valuesPerEntry;
        if (value === tagEntry.mask) {
          if (IndxParser.countSetBits(tagEntry.mask) > 1) {
            // 全位置位且多位掩码：控制字节后跟变宽字节数，再跟变宽值
            const vwi = IndxParser.variableWidthValue(entryData, dataStart);
            dataStart = vwi.next;
            pendingTag.valueBytes = vwi.value;
          } else {
            pendingTag.valueCount = 1;
          }
        } else {
          // 移位对齐掩码得到值个数
          let mask = tagEntry.mask;
          while ((mask & 0x01) === 0 && mask !== 0) {
            mask = mask >> 1;
            value = value >> 1;
          }
          pendingTag.valueCount = value;
        }
        pending.push(pendingTag);
      }
    }
    const tagHashMap = new Map<number, number[]>();
    for (const p of pending) {
      const values: number[] = [];
      if (p.valueCount >= 0) {
        for (let i = 0; i < p.valueCount; i++) {
          for (let j = 0; j < p.valuesPerEntry; j++) {
            if (dataStart >= entryData.length) {
              break;
            }
            const vwi = IndxParser.variableWidthValue(entryData, dataStart);
            dataStart = vwi.next;
            values.push(vwi.value);
          }
        }
      } else {
        let totalConsumed = 0;
        while (totalConsumed < p.valueBytes && dataStart < entryData.length) {
          const before = dataStart;
          const vwi = IndxParser.variableWidthValue(entryData, dataStart);
          dataStart = vwi.next;
          totalConsumed += vwi.next - before;
          values.push(vwi.value);
        }
      }
      tagHashMap.set(p.tag, values);
    }
    return tagHashMap;
  }
}
