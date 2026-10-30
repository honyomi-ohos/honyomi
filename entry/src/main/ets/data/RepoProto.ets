// 仓库索引 protobuf 解码模块（index.bin，schema 对齐 mihon NetworkExtensionStore，
// 源 schema 见 extension-sdk 的 packages/sdk/proto/repo_index.proto）。
// 注意：@ohos/protobufjs 3.0.2 HAR 的 dist 产物缺失 @protobufjs/codegen
// （util.codegen 未挂载），反射式 type.decode 必抛 "undefined is not callable"，
// 故宿主侧改为手写 proto3 wire 解码器：schema 固定、宿主只需 decode
// （编码始终在 Node 工具链侧经标准 protobufjs 完成，wire 兼容性由 proto3 规则保证）。
import { util } from '@kit.ArkTS';

// 仓库索引解码结果（强类型出口；extensionList 为空时 extensions 为空数组）
export interface RepoProtoStore {
  name: string;
  website: string;
  extensions: RepoProtoExtension[];
}

export interface RepoProtoExtension {
  // 插件 key（小写 UUID v4，即 packageName）
  packageName: string;
  name: string;
  apkUrl: string;
  iconUrl: string;
  versionCode: number;
  versionName: string;
  // ContentWarning 枚举数值（0 unspecified / 1 safe / 2 mixed / 3 nsfw）
  contentWarning: number;
  bt: boolean;
  // 内容类型全量列表（manga | novel | video；可多选，[0] 为主类型）
  contentTypes: string[];
  checksum: string;
  // ACGN 内容源标记（宿主据此启用 Bangumi 相关系列匹配）
  acgn: boolean;
  sources: RepoProtoSource[];
}

export interface RepoProtoSource {
  language: string;
  homeUrl: string;
}

// RepoResources 解析中间形态
interface ResourcesInfo {
  apkUrl: string;
  iconUrl: string;
}

// proto3 wire 读取器：varint / length-delimited / 未知字段跳过（前向兼容）
class WireReader {
  private buf: Uint8Array;
  private pos: number = 0;
  private decoder: util.TextDecoder;

  constructor(buf: Uint8Array) {
    this.buf = buf;
    this.decoder = util.TextDecoder.create('utf-8');
  }

  eof(): boolean {
    return this.pos >= this.buf.length;
  }

  readVarint(): number {
    let result: number = 0;
    let multiplier: number = 1;
    for (let i: number = 0; i < 10; i++) {
      if (this.pos >= this.buf.length) {
        throw new Error('proto: truncated varint');
      }
      const b: number = this.buf[this.pos];
      this.pos++;
      result += (b & 0x7f) * multiplier;
      multiplier *= 128;
      if ((b & 0x80) === 0) {
        return result;
      }
    }
    throw new Error('proto: varint too long');
  }

  // 跳过未知字段（wire 0/1/2/5；3/4 group 已废弃，抛错）
  skipField(wire: number): void {
    if (wire === 0) {
      this.readVarint();
      return;
    }
    if (wire === 1) {
      this.advance(8);
      return;
    }
    if (wire === 2) {
      const len: number = this.readVarint();
      this.advance(len);
      return;
    }
    if (wire === 5) {
      this.advance(4);
      return;
    }
    throw new Error('proto: unsupported wire type ' + wire);
  }

  readStringField(wire: number): string {
    if (wire !== 2) {
      this.skipField(wire);
      return '';
    }
    const len: number = this.readVarint();
    const bytes: Uint8Array = this.readBytes(len);
    return this.decoder.decodeToString(bytes);
  }

  readSubMessage(wire: number): WireReader | undefined {
    if (wire !== 2) {
      this.skipField(wire);
      return undefined;
    }
    const len: number = this.readVarint();
    const bytes: Uint8Array = this.readBytes(len);
    return new WireReader(bytes);
  }

  private readBytes(len: number): Uint8Array {
    this.advance(len);
    return this.buf.slice(this.pos - len, this.pos);
  }

  private advance(count: number): void {
    if (count < 0 || this.pos + count > this.buf.length) {
      throw new Error('proto: unexpected end of buffer');
    }
    this.pos += count;
  }
}

export class RepoProto {
  // ContentWarning 枚举值（对齐 mihon）：3 = NSFW
  static readonly CONTENT_WARNING_NSFW = 3;

  // ContentType 枚举值（对齐 repo_index.proto）
  static readonly CONTENT_TYPE_MANGA = 1;
  static readonly CONTENT_TYPE_NOVEL = 2;
  static readonly CONTENT_TYPE_VIDEO = 3;

  // 首字节嗅探（对齐 mihon ExtensionStoreService）：'{' / '[' → 旧 JSON 索引，其余 → protobuf
  static looksLikeRepoProto(buffer: ArrayBuffer): boolean {
    if (buffer.byteLength === 0) {
      return false;
    }
    const first: number = new Uint8Array(buffer)[0];
    return first !== 0x7b && first !== 0x5b;
  }

  // 解码仓库索引（index.bin）。二进制非法（截断 / 非法 varint / 非法 wire type）时抛错，
  // 调用方按仓库失败处理；未知字段按 proto3 前向兼容规则跳过
  static decodeRepoIndex(buffer: ArrayBuffer): RepoProtoStore {
    const reader: WireReader = new WireReader(new Uint8Array(buffer));
    let name: string = '';
    let website: string = '';
    const extensions: RepoProtoExtension[] = [];
    while (!reader.eof()) {
      const tag: number = reader.readVarint();
      const field: number = tag >>> 3;
      const wire: number = tag & 7;
      if (field === 1) {
        name = reader.readStringField(wire);
      } else if (field === 4) {
        const sub: WireReader | undefined = reader.readSubMessage(wire);
        if (sub !== undefined) {
          website = RepoProto.parseContact(sub);
        }
      } else if (field === 101) {
        const sub: WireReader | undefined = reader.readSubMessage(wire);
        if (sub !== undefined) {
          RepoProto.parseExtensionList(sub, extensions);
        }
      } else {
        // badgeLabel(2) / signingKey(3) / extensionListUrl(102)：宿主暂不消费，按未知字段跳过
        reader.skipField(wire);
      }
    }
    const store: RepoProtoStore = { name: name, website: website, extensions: extensions };
    return store;
  }

  // RepoContact：仅取 website（discord 暂不消费）
  private static parseContact(reader: WireReader): string {
    let website: string = '';
    while (!reader.eof()) {
      const tag: number = reader.readVarint();
      const field: number = tag >>> 3;
      const wire: number = tag & 7;
      if (field === 1) {
        website = reader.readStringField(wire);
      } else {
        reader.skipField(wire);
      }
    }
    return website;
  }

  private static parseExtensionList(reader: WireReader, extensions: RepoProtoExtension[]): void {
    while (!reader.eof()) {
      const tag: number = reader.readVarint();
      const field: number = tag >>> 3;
      const wire: number = tag & 7;
      if (field === 1) {
        const sub: WireReader | undefined = reader.readSubMessage(wire);
        if (sub !== undefined) {
          const ext: RepoProtoExtension | undefined = RepoProto.parseExtension(sub);
          if (ext !== undefined) {
            extensions.push(ext);
          }
        }
      } else {
        reader.skipField(wire);
      }
    }
  }

  // 单条扩展解析：packageName 缺失视为无效条目（返回 undefined 由调用方丢弃）
  private static parseExtension(reader: WireReader): RepoProtoExtension | undefined {
    let packageName: string = '';
    let name: string = '';
    let apkUrl: string = '';
    let iconUrl: string = '';
    let versionCode: number = 0;
    let versionName: string = '';
    let contentWarning: number = 0;
    let bt: boolean = false;
    let checksum: string = '';
    let acgn: boolean = false;
    const contentTypes: string[] = [];
    const sources: RepoProtoSource[] = [];
    while (!reader.eof()) {
      const tag: number = reader.readVarint();
      const field: number = tag >>> 3;
      const wire: number = tag & 7;
      if (field === 1) {
        name = reader.readStringField(wire);
      } else if (field === 2) {
        packageName = reader.readStringField(wire);
      } else if (field === 3) {
        const sub: WireReader | undefined = reader.readSubMessage(wire);
        if (sub !== undefined) {
          const res: ResourcesInfo = RepoProto.parseResources(sub);
          apkUrl = res.apkUrl;
          iconUrl = res.iconUrl;
        }
      } else if (field === 5) {
        if (wire === 0) {
          versionCode = reader.readVarint();
        } else {
          reader.skipField(wire);
        }
      } else if (field === 6) {
        versionName = reader.readStringField(wire);
      } else if (field === 7) {
        if (wire === 0) {
          contentWarning = reader.readVarint();
        } else {
          reader.skipField(wire);
        }
      } else if (field === 8) {
        const sub: WireReader | undefined = reader.readSubMessage(wire);
        if (sub !== undefined) {
          sources.push(RepoProto.parseSource(sub));
        }
      } else if (field === 9) {
        if (wire === 0) {
          bt = reader.readVarint() !== 0;
        } else {
          reader.skipField(wire);
        }
      } else if (field === 10) {
        // repeated enum：兼容 packed（wire 2）与非 packed（wire 0）两种编码
        if (wire === 2) {
          const sub: WireReader | undefined = reader.readSubMessage(wire);
          if (sub !== undefined) {
            while (!sub.eof()) {
              RepoProto.pushContentType(contentTypes, sub.readVarint());
            }
          }
        } else if (wire === 0) {
          RepoProto.pushContentType(contentTypes, reader.readVarint());
        } else {
          reader.skipField(wire);
        }
      } else if (field === 11) {
        checksum = reader.readStringField(wire);
      } else if (field === 12) {
        if (wire === 0) {
          acgn = reader.readVarint() !== 0;
        } else {
          reader.skipField(wire);
        }
      } else {
        // extensionLib(4)：宿主暂不消费，按未知字段跳过
        reader.skipField(wire);
      }
    }
    if (packageName === '') {
      return undefined;
    }
    // 内容类型全量列表（主类型在前）；未声明回退 [manga]
    if (contentTypes.length === 0) {
      contentTypes.push('manga');
    }
    const ext: RepoProtoExtension = {
      packageName: packageName,
      name: name !== '' ? name : packageName,
      apkUrl: apkUrl,
      iconUrl: iconUrl,
      versionCode: versionCode,
      versionName: versionName,
      contentWarning: contentWarning,
      bt: bt,
      contentTypes: contentTypes,
      checksum: checksum,
      acgn: acgn,
      sources: sources,
    };
    return ext;
  }

  private static parseResources(reader: WireReader): ResourcesInfo {
    let apkUrl: string = '';
    let iconUrl: string = '';
    while (!reader.eof()) {
      const tag: number = reader.readVarint();
      const field: number = tag >>> 3;
      const wire: number = tag & 7;
      if (field === 1) {
        apkUrl = reader.readStringField(wire);
      } else if (field === 2) {
        iconUrl = reader.readStringField(wire);
      } else {
        reader.skipField(wire);
      }
    }
    const res: ResourcesInfo = { apkUrl: apkUrl, iconUrl: iconUrl };
    return res;
  }

  // RepoSource：宿主仅消费 language / homeUrl（id/name/mirrorUrls/message 暂不消费）
  private static parseSource(reader: WireReader): RepoProtoSource {
    let language: string = '';
    let homeUrl: string = '';
    while (!reader.eof()) {
      const tag: number = reader.readVarint();
      const field: number = tag >>> 3;
      const wire: number = tag & 7;
      if (field === 3) {
        language = reader.readStringField(wire);
      } else if (field === 4) {
        homeUrl = reader.readStringField(wire);
      } else {
        reader.skipField(wire);
      }
    }
    const source: RepoProtoSource = { language: language, homeUrl: homeUrl };
    return source;
  }

  // ContentType 枚举数值 → 字符串（去重入列；未知值丢弃）
  private static pushContentType(contentTypes: string[], value: number): void {
    const mapped: string = RepoProto.contentTypeFromProto(value);
    if (mapped !== '' && contentTypes.indexOf(mapped) < 0) {
      contentTypes.push(mapped);
    }
  }

  // ContentType 枚举数值 → 字符串（未知值返回 '' 由调用方丢弃）
  private static contentTypeFromProto(value: number): string {
    if (value === RepoProto.CONTENT_TYPE_NOVEL) {
      return 'novel';
    }
    if (value === RepoProto.CONTENT_TYPE_VIDEO) {
      return 'video';
    }
    if (value === RepoProto.CONTENT_TYPE_MANGA) {
      return 'manga';
    }
    return '';
  }
}
