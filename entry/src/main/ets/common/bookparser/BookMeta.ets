// book.json 落盘模型与落盘逻辑。
// 独立模块：@Concurrent 任务内只能引用 import 变量，本文件的类需被 BookParserTasks 导入使用。

import { BookFileIo } from './ByteUtils';

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
