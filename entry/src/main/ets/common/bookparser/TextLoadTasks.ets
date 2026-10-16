// taskpool @Concurrent 章节文本加载任务：本地 txt / 书籍章节缓存文件的读取与解码移出主线程，
// 避免大章节同步 IO + 编码探测链阻塞 UI。
// @Concurrent 函数不可捕获闭包：仅可使用参数与 import 变量。

import { taskpool } from '@kit.ArkTS';
import { AutoTextDecode } from './AutoTextDecode';

// 智能读取文本文件（编码自动识别），在 taskpool 线程执行
@Concurrent
export function readTextAutoTask(path: string): string {
  return AutoTextDecode.readFileAuto(path);
}

// 异步读取文本文件（编码自动识别）：解码在 taskpool 线程，主线程仅收字符串
export async function readTextAutoAsync(path: string): Promise<string> {
  try {
    const result = await taskpool.execute(readTextAutoTask, path);
    if (typeof result !== 'string') {
      throw new Error('read_text_failed');
    }
    return result;
  } catch (e) {
    throw new Error('read_text_failed');
  }
}
