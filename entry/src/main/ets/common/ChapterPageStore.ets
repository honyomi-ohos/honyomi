import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SPage } from '../model/Models';
import { ArchiveReader } from './ArchiveReader';

// 章节页文件持久层（L0）：下载目录布局 {filesDir}/downloads/{mangaId}/{chapterId}/，
// 页文件命名 pad(index).jpg（超长图切片 pad(index)__NN.jpg），目录内共存 done.mark/chapter.txt/video.* 等非页产物。
// 阅读管线与下载编排共同依赖本层，互不感知：
// - 下载编排（DownloadService）：写入/清理页文件，按"文件存在即完整"断点续传
// - 阅读管线（ReaderPage）：读取本地页列表、在线阅读时替换已落盘页
// 原子写不变量：正式页文件只经 tmp → rename 落位，进程任意时刻被杀都不会留下半截文件
export class ChapterPageStore {
  static rootDir: string = '';
  private static context: common.UIAbilityContext | undefined = undefined;

  static init(context: common.UIAbilityContext): void {
    ChapterPageStore.context = context;
    ChapterPageStore.rootDir = `${context.filesDir}/downloads`;
    try {
      if (!fileIo.accessSync(ChapterPageStore.rootDir)) {
        fileIo.mkdirSync(ChapterPageStore.rootDir, true);
      }
    } catch (e) {
      throw new Error(`init download dir failed: ${e}`);
    }
  }

  static chapterDir(mangaId: number, chapterId: number): string {
    return `${ChapterPageStore.rootDir}/${mangaId}/${chapterId}`;
  }

  static pad(index: number): string {
    const s = `${index}`;
    if (s.length >= 3) {
      return s;
    }
    let out = s;
    while (out.length < 3) {
      out = `0${out}`;
    }
    return out;
  }

  // 章节目录下的零散页文件列表（排除非页产物，按文件名排序保证页序）
  static localPages(mangaId: number, chapterId: number): string[] {
    const dir = ChapterPageStore.chapterDir(mangaId, chapterId);
    try {
      if (!fileIo.accessSync(dir)) {
        return [];
      }
      const files = fileIo.listFileSync(dir);
      const pages = files.filter((f: string) => f !== 'done.mark' && f !== 'chapter.txt' &&
        f !== 'video.mp4' && f !== 'video.ts' && f !== 'chapter.cbz' && f !== 'extract.ok').sort();
      const result: string[] = [];
      for (const f of pages) {
        result.push(`${dir}/${f}`);
      }
      return result;
    } catch (e) {
      throw new Error(`list local pages failed: ${e}`);
    }
  }

  // 本地页面（异步版）：CBZ 章节首次阅读时解压到缓存目录后返回图片路径
  static async localPagesAsync(mangaId: number, chapterId: number): Promise<string[]> {
    const dir = ChapterPageStore.chapterDir(mangaId, chapterId);
    try {
      if (!fileIo.accessSync(dir)) {
        return [];
      }
      const cbz = `${dir}/chapter.cbz`;
      if (fileIo.accessSync(cbz)) {
        return await ChapterPageStore.extractCbzPages(cbz, mangaId, chapterId);
      }
    } catch (e) {
      throw new Error(`check local pages failed: ${e}`);
    }
    return ChapterPageStore.localPages(mangaId, chapterId);
  }

  // CBZ 读取：解压到 cacheDir/cbz_extract/{mangaId}/{chapterId}，extract.ok 标记完整性；
  // 缓存被系统清理或上次解压中断时自动重解
  private static async extractCbzPages(cbzPath: string, mangaId: number,
    chapterId: number): Promise<string[]> {
    const ctx = ChapterPageStore.context;
    if (ctx === undefined) {
      throw new Error('download_not_ready');
    }
    const extractDir = `${ctx.cacheDir}/cbz_extract/${mangaId}/${chapterId}`;
    const markPath = `${extractDir}/extract.ok`;
    try {
      if (!fileIo.accessSync(markPath)) {
        if (fileIo.accessSync(extractDir)) {
          ChapterPageStore.rmdir(extractDir);
        }
        fileIo.mkdirSync(extractDir, true);
        // 统一走归档分派层（chapter.cbz 为 zip 格式，zlib 解压）
        await ArchiveReader.openArchive(cbzPath, extractDir);
        const fd = fileIo.openSync(markPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd;
        fileIo.closeSync(fd);
      }
    } catch (e) {
      try {
        if (fileIo.accessSync(extractDir)) {
          ChapterPageStore.rmdir(extractDir);
        }
      } catch (_e) {
      }
      throw new Error(`extract cbz failed: ${e}`);
    }
    return ChapterPageStore.listImagesRecursive(extractDir);
  }

  // 递归列出目录下全部图片文件（解压产物可能是嵌套目录结构，按文件名排序保证页序）
  private static listImagesRecursive(dir: string): string[] {
    const out: string[] = [];
    try {
      if (!fileIo.accessSync(dir)) {
        return out;
      }
      const files = fileIo.listFileSync(dir).sort();
      for (const f of files) {
        const p = `${dir}/${f}`;
        let isDir = false;
        try {
          isDir = fileIo.statSync(p).isDirectory();
        } catch (_e) {
          continue;
        }
        if (isDir) {
          const nested = ChapterPageStore.listImagesRecursive(p);
          for (const n of nested) {
            out.push(n);
          }
        } else if (ChapterPageStore.isImageFile(f)) {
          out.push(p);
        }
      }
    } catch (e) {
      throw new Error(`list cbz images failed: ${e}`);
    }
    return out;
  }

  private static isImageFile(name: string): boolean {
    const lower = name.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') ||
      lower.endsWith('.webp') || lower.endsWith('.gif');
  }

  // 删除章节时同步清理 CBZ 解压缓存
  static clearExtractCache(mangaId: number, chapterId: number): void {
    const ctx = ChapterPageStore.context;
    if (ctx === undefined) {
      return;
    }
    const extractDir = `${ctx.cacheDir}/cbz_extract/${mangaId}/${chapterId}`;
    try {
      if (fileIo.accessSync(extractDir)) {
        ChapterPageStore.rmdir(extractDir);
      }
    } catch (e) {
      hilog.warn(0x0001, 'PageStore', 'clear extract cache failed: %{public}s', `${e}`);
    }
  }

  // 部分下载复用：在线阅读时把已落盘的下载页替换进在线页列表——
  // 章节下载进行中/中断（无 done.mark）时，已完整下载的页不再经网络重复加载。
  // 仅替换完整的 {NNN}.jpg 正式页；已被切片的超长图（目录中仅存 {NNN}__NN.jpg 切片）
  // 保留在线 URL，页数结构不变，阅读进度不随下载推进而漂移。
  // 列表结构（顺序/页数/索引）保持不变，仅 url 由 http(s) 替换为 file://
  static substituteDownloadedPages(mangaId: number, chapterId: number, pages: SPage[]): SPage[] {
    if (ChapterPageStore.rootDir === '' || pages.length === 0) {
      return pages;
    }
    const dir = ChapterPageStore.chapterDir(mangaId, chapterId);
    try {
      if (!fileIo.accessSync(dir)) {
        return pages;
      }
    } catch (_e) {
      return pages;
    }
    const out: SPage[] = [];
    let substituted = false;
    for (let i = 0; i < pages.length; i++) {
      const p = pages[i];
      const local = `${dir}/${ChapterPageStore.pad(p.index)}.jpg`;
      let hit = false;
      try {
        hit = fileIo.accessSync(local);
      } catch (_e) {
        hit = false;
      }
      if (hit) {
        out.push({ index: p.index, url: `file://${local}` });
        substituted = true;
      } else {
        out.push(p);
      }
    }
    return substituted ? out : pages;
  }

  // 原子写单页：先写 .tmp 再改名落位，进程任意时刻被杀都不会留下半截正式页文件，
  // 从而重启后可按"文件存在即完整"安全断点续传
  static writePageFile(path: string, buffer: ArrayBuffer): void {
    const tmp = `${path}.tmp`;
    let fd: number = -1;
    try {
      fd = fileIo.openSync(tmp,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC).fd;
      fileIo.writeSync(fd, buffer);
    } catch (e) {
      throw new Error(`write_page_failed: ${e}`);
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd);
        } catch (e) {
        }
      }
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path);
      }
      fileIo.renameSync(tmp, path);
    } catch (e) {
      throw new Error(`write_page_failed: ${e}`);
    }
  }

  // 原子复制单页（浏览缓存 → 下载目录）：与 writePageFile 同语义，
  // tmp → rename 保证"文件存在即完整"的断点续传不变量；复制失败抛错由调用方回退网络
  static copyCachedPage(src: string, dest: string): void {
    const tmp = `${dest}.tmp`;
    try {
      fileIo.copyFileSync(src, tmp);
      if (fileIo.accessSync(dest)) {
        fileIo.unlinkSync(dest);
      }
      fileIo.renameSync(tmp, dest);
    } catch (e) {
      try {
        if (fileIo.accessSync(tmp)) {
          fileIo.unlinkSync(tmp);
        }
      } catch (_e) {
      }
      throw new Error(`copy_page_failed: ${e}`);
    }
  }

  // 清理目录内残留的半截 .tmp 文件
  static cleanTmpFiles(dir: string): void {
    try {
      if (!fileIo.accessSync(dir)) {
        return;
      }
      const files = fileIo.listFileSync(dir);
      for (const f of files) {
        if (f.endsWith('.tmp')) {
          fileIo.unlinkSync(`${dir}/${f}`);
        }
      }
    } catch (e) {
    }
  }

  // 删除编号超出当前页数的旧页文件（页列表缩短场景，避免旧图混入）
  static removeStalePages(dir: string, pageCount: number): void {
    try {
      if (!fileIo.accessSync(dir)) {
        return;
      }
      const files = fileIo.listFileSync(dir);
      for (const f of files) {
        if (!f.endsWith('.jpg')) {
          continue;
        }
        const idx = parseInt(f.substring(0, f.length - 4), 10);
        if (!Number.isNaN(idx) && idx >= pageCount) {
          fileIo.unlinkSync(`${dir}/${f}`);
        }
      }
    } catch (e) {
    }
  }

  // 递归删除下载存储树/解压缓存下的文件或目录
  static rmdir(path: string): void {
    try {
      if (!fileIo.accessSync(path)) {
        return;
      }
      const stat = fileIo.statSync(path);
      if (stat.isDirectory()) {
        const children = fileIo.listFileSync(path);
        for (const c of children) {
          ChapterPageStore.rmdir(`${path}/${c}`);
        }
        fileIo.rmdirSync(path);
      } else {
        fileIo.unlinkSync(path);
      }
    } catch (e) {
      throw new Error(`rmdir ${path} failed: ${e}`);
    }
  }
}
