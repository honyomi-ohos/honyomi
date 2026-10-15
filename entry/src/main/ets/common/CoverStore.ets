import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImageCache } from './ImageCache';
import { PluginService } from '../data/PluginService';

// 自定义封面文件管理（对齐 Mihon custom cover 目录）：
// 选中图片复制到 filesDir/custom_covers/{mangaId}.{ext}，路径以 file:// 写入 manga.thumbnailUrl
export class CoverStore {
  // 书架持久化封面进行中的任务（按 mangaId 去重，避免回填与入库并发重复落盘）
  private static persisting: Map<number, Promise<string>> = new Map();

  // 持久化书架封面：经 ImageCache 管线下载（AVIF→JPEG 转码）后复制到 files/covers/{mangaId}.jpg
  // 返回裸绝对路径；非 http(s) 源或失败返回 ''
  static persistFromUrl(context: common.Context, mangaId: number, url: string, sourceKey: string): Promise<string> {
    const running = CoverStore.persisting.get(mangaId);
    if (running !== undefined) {
      return running;
    }
    const task = CoverStore.doPersistFromUrl(context, mangaId, url, sourceKey);
    CoverStore.persisting.set(mangaId, task);
    task.then((): void => {
      CoverStore.persisting.delete(mangaId);
    }, (): void => {
      CoverStore.persisting.delete(mangaId);
    });
    return task;
  }

  // 复制选中的图片为自定义封面，返回 file:// 路径；失败返回 ''
  static async save(context: common.Context, mangaId: number, uri: string): Promise<string> {
    try {
      const dir = CoverStore.ensureDir(context);
      CoverStore.purge(dir, mangaId);
      let ext = '.jpg';
      const q = uri.indexOf('?');
      const path = q >= 0 ? uri.substring(0, q) : uri;
      const dot = path.lastIndexOf('.');
      if (dot >= 0 && path.length - dot <= 6) {
        ext = path.substring(dot);
      }
      const dest = `${dir}/${mangaId}${ext}`;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(src.fd, dest);
      } finally {
        fs.closeSync(src);
      }
      return `file://${dest}`;
    } catch (_e) {
      // 复制失败（源文件被删/URI 失效等）：告警便于排障，调用方按返回 '' 判定失败
      hilog.warn(0x0000, 'CoverStore', 'save custom cover failed: %{public}s', `${_e}`);
      return '';
    }
  }

  // 删除自定义封面文件（恢复原封面时调用）
  static remove(context: common.Context, mangaId: number): void {
    try {
      const dir = `${context.filesDir}/custom_covers`;
      if (!fs.accessSync(dir)) {
        return;
      }
      CoverStore.purge(dir, mangaId);
    } catch (e) {
      // 目录不存在等场景忽略
    }
  }

  private static async doPersistFromUrl(context: common.Context, mangaId: number, url: string,
    sourceKey: string): Promise<string> {
    if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
      return '';
    }
    try {
      // 冷启动竞态：插件源可能尚未注册（无请求头下载会失败/拿错内容），限时等待注册完成
      await Promise.race([
        PluginService.ready(),
        new Promise<void>((resolve: (value: void) => void): void => {
          setTimeout((): void => {
            resolve();
          }, 10000);
        })
      ]);
      const cached = await ImageCache.ensureLocal(context, url, sourceKey);
      if (cached === '') {
        return '';
      }
      const srcPath = cached.indexOf('file://') === 0 ? cached.substring('file://'.length) : cached;
      const dir = `${context.filesDir}/covers`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const dest = `${dir}/${mangaId}.jpg`;
      const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(src.fd, dest);
      } finally {
        fs.closeSync(src);
      }
      return dest;
    } catch (e) {
      hilog.warn(0x0000, 'CoverStore', 'persist cover failed mangaId=%{public}d: %{public}s',
        mangaId, `${e}`);
      return '';
    }
  }

  // ---------------- 内部实现 ----------------

  private static ensureDir(context: common.Context): string {
    const dir = `${context.filesDir}/custom_covers`;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      throw new Error(`ensure cover dir failed: ${e}`);
    }
    return dir;
  }

  // 清掉该漫画旧的自定义封面（扩展名可能不同）
  private static purge(dir: string, mangaId: number): void {
    try {
      const prefix = `${mangaId}.`;
      const names = fs.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        if (names[i].lastIndexOf(prefix, 0) === 0) {
          fs.unlinkSync(`${dir}/${names[i]}`);
        }
      }
    } catch (e) {
      throw new Error(`purge covers failed: ${e}`);
    }
  }
}
