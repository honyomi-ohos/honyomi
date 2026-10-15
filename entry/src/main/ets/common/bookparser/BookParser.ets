// 书籍解析 facade：缓存目录管理（FNV-1a 哈希键）、epub 解压（主线程 zlib）、
// taskpool 任务调度与 in-flight 去重、book.json 读取、章节文本加载。
// 模型流转：task 返回 JSON → JSON.parse(x) as BookMetaRaw（一次转换）→ BookInfo。

import { zlib } from '@kit.BasicServicesKit';
import { BookFileIo, BookTextCodec } from './ByteUtils';
import { BookMetaRaw, BookPersist, parseEpubBookTask, parseMobiBookTask } from './BookParserTasks';

// 面向调用方（本地小说源）的解析结果
export class BookInfo {
  title: string = '';
  author: string = '';
  coverPath: string = '';
  chapterNames: string[] = [];
}

export class BookParser {
  private static filesDir: string = '';
  private static inFlight: Map<string, Promise<BookInfo>> = new Map();
  private static readonly BOOK_EXTS: string[] = ['.epub', '.mobi', '.azw', '.azw3', '.prc'];

  // 由本地源构造时注入应用沙箱 filesDir
  static init(filesDir: string): void {
    BookParser.filesDir = filesDir;
  }

  static bookExts(): string[] {
    return BookParser.BOOK_EXTS;
  }

  static isBookFile(name: string): boolean {
    const lower = name.toLowerCase();
    for (const ext of BookParser.BOOK_EXTS) {
      if (lower.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  // 缓存目录：<filesDir>/book_cache/<fnv1a(path|mtime|size)>
  static cacheDirOf(path: string): string {
    const statKey = `${path}|${BookFileIo.mtime(path)}|${BookFileIo.fileSize(path)}`;
    return `${BookParser.filesDir}/book_cache/${BookParser.fnv1a(statKey)}`;
  }

  // 解析书籍（命中缓存直接返回；in-flight 去重避免并发重复解析）
  static async parse(path: string): Promise<BookInfo> {
    const pending = BookParser.inFlight.get(path);
    if (pending !== undefined) {
      return pending;
    }
    const cacheDir = BookParser.cacheDirOf(path);
    const cached = BookParser.loadCached(cacheDir);
    if (cached !== null) {
      return cached;
    }
    const task = BookParser.doParse(path, cacheDir);
    BookParser.inFlight.set(path, task);
    try {
      return await task;
    } finally {
      BookParser.inFlight.delete(path);
    }
  }

  // 加载章节文本（解析已完成，缓存必命中）
  static loadChapterText(path: string, index: number): string {
    const cacheDir = BookParser.cacheDirOf(path);
    const text = BookFileIo.readText(`${cacheDir}/chapters/${BookPersist.chapterFile(index)}`);
    if (text === null) {
      throw new Error('chapter_missing');
    }
    return text;
  }

  // ---------------- 内部实现 ----------------

  private static async doParse(path: string, cacheDir: string): Promise<BookInfo> {
    BookFileIo.ensureDir(cacheDir);
    const lower = path.toLowerCase();
    let json = '';
    if (lower.endsWith('.epub') || BookParser.isZipFile(path)) {
      json = await BookParser.parseEpub(path, cacheDir);
    } else {
      const result = await BookParser.runTask(parseMobiBookTask, path, cacheDir);
      json = result;
    }
    return BookParser.toBookInfo(json);
  }

  private static async parseEpub(path: string, cacheDir: string): Promise<string> {
    const extractDir = `${cacheDir}/extract`;
    if (!BookFileIo.exists(`${extractDir}/META-INF/container.xml`)) {
      // 清理可能的半成品解压目录后重新解压
      BookFileIo.removeQuietly(extractDir);
      BookFileIo.ensureDir(extractDir);
      await zlib.decompressFile(path, extractDir);
    }
    return BookParser.runTask(parseEpubBookTask, extractDir, cacheDir);
  }

  // taskpool.execute 返回 Promise<Object|void>，typeof 收窄为 string（不用 as）
  private static async runTask(task: (a: string, b: string) => string,
    arg1: string, arg2: string): Promise<string> {
    const result = await taskpool.execute(task, arg1, arg2);
    if (typeof result !== 'string') {
      throw new Error('book_parse_failed');
    }
    return result;
  }

  private static isZipFile(path: string): boolean {
    const head = BookFileIo.readHead(path, 4);
    if (head === null || head.length < 4) {
      return false;
    }
    return head[0] === 0x50 && head[1] === 0x4B && head[2] === 0x03 && head[3] === 0x04;
  }

  private static loadCached(cacheDir: string): BookInfo | null {
    const json = BookFileIo.readText(`${cacheDir}/book.json`);
    if (json === null) {
      return null;
    }
    try {
      return BookParser.toBookInfo(json);
    } catch (e) {
      return null;
    }
  }

  private static toBookInfo(json: string): BookInfo {
    const raw = JSON.parse(json) as BookMetaRaw;
    if (typeof raw.title !== 'string' || !Array.isArray(raw.names)) {
      throw new Error('book_cache_corrupt');
    }
    const info = new BookInfo();
    info.title = raw.title;
    info.author = typeof raw.author === 'string' ? raw.author : '';
    info.coverPath = typeof raw.cover === 'string' ? raw.cover : '';
    info.chapterNames = raw.names;
    return info;
  }

  // FNV-1a 32 位哈希 → 十六进制（缓存键）
  private static fnv1a(s: string): string {
    const bytes = BookTextCodec.encodeUtf8(s);
    let hash = 0x811C9DC5 | 0;
    for (let i = 0; i < bytes.length; i++) {
      hash = Math.imul(hash ^ bytes[i], 0x01000193);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
  }
}
