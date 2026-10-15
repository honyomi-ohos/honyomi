// taskpool @Concurrent 书籍解析任务 + 解析结果落盘。
// 任务返回 JSON 字符串（规避 taskpool 序列化限制），由 facade JSON.parse 归一。
// @Concurrent 函数不可捕获闭包：仅可使用参数与 import。

import { taskpool } from '@kit.ArkTS';
import { BookFileIo } from './ByteUtils';
import { MobiBookParser } from './MobiBookParser';
import { EpubParser } from './EpubParser';

// book.json 落盘模型（JSON.parse 后 as 一次转换，许可模式）
export class BookMetaRaw {
  title: string = '';
  author: string = '';
  cover: string = '';
  names: string[] = [];
}

// 解析结果落盘：chapters/NNNN.txt + book.json；返回 book.json 内容
export class BookPersist {
  static chapterFile(index: number): string {
    return `${(index + 1).toString().padStart(4, '0')}.txt`;
  }

  static persist(cacheDir: string, title: string, author: string, cover: string,
    chapters: string[], names: string[]): string {
    BookFileIo.ensureDir(`${cacheDir}/chapters`);
    for (let i = 0; i < chapters.length; i++) {
      BookFileIo.writeText(`${cacheDir}/chapters/${BookPersist.chapterFile(i)}`, chapters[i]);
    }
    const meta = new BookMetaRaw();
    meta.title = title;
    meta.author = author;
    meta.cover = cover;
    meta.names = names;
    const json = JSON.stringify(meta);
    BookFileIo.writeText(`${cacheDir}/book.json`, json);
    return json;
  }
}

// MOBI/AZW/PRC 解析任务：整文件读取 → 解析 → 图片/章节落盘 → book.json
@Concurrent
export function parseMobiBookTask(path: string, cacheDir: string): string {
  const bytes = BookFileIo.readBytes(path);
  if (bytes === null || bytes.length === 0) {
    throw new Error('book_read_failed');
  }
  const result = MobiBookParser.parse(bytes, cacheDir);
  return BookPersist.persist(cacheDir, result.title, result.author, result.coverPath,
    result.chapters, result.chapterNames);
}

// EPUB 解析任务：extractDir 为已解压目录（facade 主线程 zlib.decompressFile 完成）
@Concurrent
export function parseEpubBookTask(extractDir: string, cacheDir: string): string {
  const result = EpubParser.parse(extractDir);
  return BookPersist.persist(cacheDir, result.title, result.author, result.coverPath,
    result.chapters, result.chapterNames);
}
