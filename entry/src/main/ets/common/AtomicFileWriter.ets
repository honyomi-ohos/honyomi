import { fileIo as fs } from '@kit.CoreFileKit';

// 原子落盘共享原语：时间戳+序号 .tmp → rename，失败清理残留；
// 供 ImageCache / BgmCoverCache / EmojiCache 共用，统一多进程/多任务并发写防护
// 与进程被杀残留 .tmp 的清扫（此前三份拷贝已出现固定 .tmp 后缀的并发缺陷漂移）
export class AtomicFileWriter {
  private static seq: number = 0;
  // 进程被杀残留的 .tmp 清扫保留期（1 小时）
  private static readonly TMP_TTL_MS: number = 3600000;

  // 原子写入：临时文件名带时间戳+序号，多进程/多任务并发写同一目标也不会互相覆盖；
  // 目标已存在（并发竞态，对方先完成 rename）时丢弃临时文件并返回 true（existed），
  // 新写入成功返回 false；失败抛错并清理 .tmp 残留
  static write(path: string, buffer: ArrayBuffer): boolean {
    const tmp = `${path}.${Date.now()}.${AtomicFileWriter.seq++}.tmp`;
    let existed = false;
    try {
      const file = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      if (!fs.accessSync(path)) {
        fs.renameSync(tmp, path);
      } else {
        fs.unlinkSync(tmp);
        existed = true;
      }
    } catch (e) {
      // 失败/异常路径清理 .tmp 残留
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (_e) {
      }
      throw new Error((e as Error).message);
    }
    return existed;
  }

  // 清理超过保留期的 .tmp 残留（进程被杀时未及 rename 的下载半成品）；
  // 各缓存 init 时延后一拍调用一次
  static sweepTmp(dir: string): void {
    try {
      const names = fs.listFileSync(dir);
      const now = Date.now();
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (name.indexOf('.tmp') !== name.length - '.tmp'.length) {
          continue;
        }
        const stat = fs.statSync(`${dir}/${name}`);
        const mtimeMs = stat.mtime * 1000;
        if (now - mtimeMs > AtomicFileWriter.TMP_TTL_MS) {
          fs.unlinkSync(`${dir}/${name}`);
        }
      }
    } catch (_e) {
    }
  }
}
