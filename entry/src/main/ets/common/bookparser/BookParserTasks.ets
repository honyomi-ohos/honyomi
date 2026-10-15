// taskpool @Concurrent 书籍解析任务。
// 任务返回 JSON 字符串（规避 taskpool 序列化限制），由 facade JSON.parse 归一。
// @Concurrent 函数不可捕获闭包：仅可使用参数与 import 变量。

import { MobiBookParser } from './MobiBookParser';
import { EpubParser } from './EpubParser';
import { BookFileIo } from './ByteUtils';
import { BookPersist } from './BookMeta';

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
