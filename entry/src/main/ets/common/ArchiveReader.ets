// 归档格式统一识别与解包分派（对齐 Mihon Archive.isSupported 的格式集：
// zip/cbz/rar/cbr/7z/cb7/tar/cbt）。
// - zip/cbz：zlib.decompressFile（系统内置，沿用既有逻辑）
// - tar/cbt：纯 ArkTS TarExtractor（common/TarExtractor.ets）
// - rar/cbr、7z/cb7：鸿蒙无系统解码器，纯 ArkTS 实现 RAR VM / 7z LZMA+BCJ
//   解码链不现实（已定裁剪决策），识别后抛出带中文文案的业务错误，
//   由阅读页 errText 兜底（未识别错误码原样 toast 展示）
import { zlib } from '@kit.BasicServicesKit';
import { TarExtractor } from './TarExtractor';

// 归档格式识别（按扩展名）
export class ArchiveFormat {
  private static readonly ZIP_EXTS: string[] = ['.zip', '.cbz'];
  private static readonly TAR_EXTS: string[] = ['.tar', '.cbt'];
  private static readonly RAR_EXTS: string[] = ['.rar', '.cbr'];
  private static readonly SZ_EXTS: string[] = ['.7z', '.cb7'];

  // 全部受支持的归档扩展（含仅识别不解码的 rar/7z 系）
  static supportedExts(): string[] {
    return ArchiveFormat.ZIP_EXTS.concat(ArchiveFormat.TAR_EXTS)
      .concat(ArchiveFormat.RAR_EXTS)
      .concat(ArchiveFormat.SZ_EXTS);
  }

  static isZip(name: string): boolean {
    return ArchiveFormat.matchExt(name, ArchiveFormat.ZIP_EXTS);
  }

  static isTar(name: string): boolean {
    return ArchiveFormat.matchExt(name, ArchiveFormat.TAR_EXTS);
  }

  static isRar(name: string): boolean {
    return ArchiveFormat.matchExt(name, ArchiveFormat.RAR_EXTS);
  }

  static is7z(name: string): boolean {
    return ArchiveFormat.matchExt(name, ArchiveFormat.SZ_EXTS);
  }

  static isSupported(name: string): boolean {
    return ArchiveFormat.isZip(name) || ArchiveFormat.isTar(name) ||
      ArchiveFormat.isRar(name) || ArchiveFormat.is7z(name);
  }

  // 去掉归档扩展名（解压缓存目录命名用）；非归档名兜底去最后一个扩展名
  static stripArchiveExt(name: string): string {
    const lower = name.toLowerCase();
    const all = ArchiveFormat.supportedExts();
    for (const ext of all) {
      if (lower.endsWith(ext)) {
        return name.substring(0, name.length - ext.length);
      }
    }
    const dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  private static matchExt(name: string, exts: string[]): boolean {
    const lower = name.toLowerCase();
    for (const ext of exts) {
      if (lower.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }
}

// 归档解包统一入口：按扩展名分派到对应解码器，全部条目解出到 outDir
export class ArchiveReader {
  static async openArchive(archivePath: string, outDir: string): Promise<void> {
    const fileName = archivePath.substring(archivePath.lastIndexOf('/') + 1);
    if (ArchiveFormat.isZip(fileName)) {
      try {
        await zlib.decompressFile(archivePath, outDir);
      } catch (e) {
        throw new Error(`zip 解压失败：${e instanceof Error ? e.message : String(e)}`);
      }
      return;
    }
    if (ArchiveFormat.isTar(fileName)) {
      await TarExtractor.extract(archivePath, outDir);
      return;
    }
    if (ArchiveFormat.isRar(fileName)) {
      throw new Error('暂不支持 RAR/CBR 格式，请转换为 ZIP/CBZ');
    }
    if (ArchiveFormat.is7z(fileName)) {
      throw new Error('暂不支持 7z/CB7 格式，请转换为 ZIP/CBZ');
    }
    throw new Error('unsupported_format');
  }
}
