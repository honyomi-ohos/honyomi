// 纯 ArkTS tar 解包对外入口（对齐 Mihon 支持的 tar/cbt 格式）。
// 解析核心在 common/TarCore.ets；解码在 taskpool 后台线程执行，避免大归档阻塞 UI。

import { taskpool } from '@kit.ArkTS';
import { TarCore } from './TarCore';

// taskpool 后台解包任务（@Concurrent 仅可引用导入变量或局部变量，故 TarCore 独立成模块）
@Concurrent
export function tarExtractTask(tarPath: string, outDir: string): string {
  TarCore.extractTo(tarPath, outDir);
  return 'ok';
}

// tar/cbt 解包对外入口：后台线程解出到 outDir
export class TarExtractor {
  static async extract(tarPath: string, outDir: string): Promise<void> {
    try {
      await taskpool.execute(tarExtractTask, tarPath, outDir);
    } catch (e) {
      throw new Error(e instanceof Error && e.message !== '' ? e.message : 'tar 解压失败');
    }
  }
}
