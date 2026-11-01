import { fileIo as fs } from '@kit.CoreFileKit';

// 磁盘缓存文件元信息（超预算时按 mtime 淘汰最旧文件）
interface LruFileMeta {
  name: string;
  mtime: number;
  size: number;
}

// 磁盘缓存字节预算引擎（共享原语）：目录字节记账 + 超预算按 mtime LRU 淘汰；
// 供 ImageCache / BgmCoverCache 共用（此前两份 evictOldest/noteWrite/rescanBytes
// 拷贝约 150 行重复）。启动路径不做同步全量统计：init 后延后一拍 rescan 一次，
// 写入走 noteWrite 增量维护；淘汰在超预算时延后一拍触发
export class LruBudget {
  private dir: string;
  private readonly maxBytes: number;
  private totalBytes: number = 0;
  private evicting: boolean = false;

  constructor(dir: string, maxBytes: number) {
    this.dir = dir;
    this.maxBytes = maxBytes;
  }

  // 全量统计目录字节数（作为超预算判定的基准）
  rescan(): void {
    try {
      if (!fs.accessSync(this.dir)) {
        return;
      }
      let total = 0;
      const names = fs.listFileSync(this.dir);
      for (let i = 0; i < names.length; i++) {
        try {
          total += fs.statSync(`${this.dir}/${names[i]}`).size;
        } catch (_e) {
        }
      }
      this.totalBytes = total;
    } catch (_e) {
      // 统计失败保持现值：预算判定退化为准确值恢复前略偏，不影响正确性
    }
  }

  // 写入成功后增量累计字节，超预算时延后一拍触发 LRU 淘汰
  noteWrite(bytes: number): void {
    this.totalBytes += bytes;
    if (this.totalBytes > this.maxBytes && !this.evicting) {
      this.evicting = true;
      setTimeout((): void => {
        try {
          this.evictOldest();
        } finally {
          this.evicting = false;
        }
      }, 0);
    }
  }

  // 清空缓存目录后归零记账基准（与目录实际删除异步解耦，删除完成后无需重扫）
  reset(): void {
    this.totalBytes = 0;
  }

  // 超预算时按 mtime 淘汰最旧文件，直到回到预算内
  private evictOldest(): void {
    try {
      if (!fs.accessSync(this.dir)) {
        return;
      }
      const names = fs.listFileSync(this.dir);
      const metas: LruFileMeta[] = [];
      for (let i = 0; i < names.length; i++) {
        try {
          const stat = fs.statSync(`${this.dir}/${names[i]}`);
          const meta: LruFileMeta = { name: names[i], mtime: stat.mtime, size: stat.size };
          metas.push(meta);
        } catch (_e) {
        }
      }
      metas.sort((a: LruFileMeta, b: LruFileMeta): number => a.mtime - b.mtime);
      for (let i = 0; i < metas.length; i++) {
        if (this.totalBytes <= this.maxBytes) {
          break;
        }
        try {
          fs.unlinkSync(`${this.dir}/${metas[i].name}`);
          this.totalBytes -= metas[i].size;
          if (this.totalBytes < 0) {
            this.totalBytes = 0;
          }
        } catch (_e) {
        }
      }
    } catch (_e) {
      // 淘汰在 setTimeout 内执行，异常无处上抛：静默保底（下次写入超预算会再次触发）
    }
  }
}
