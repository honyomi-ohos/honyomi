import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 自定义封面文件管理（对齐 Mihon custom cover 目录）：
// 选中图片复制到 filesDir/custom_covers/{mangaId}.{ext}，路径以 file:// 写入 manga.thumbnailUrl
export class CoverStore {
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

  // ---------------- 内部实现 ----------------

  private static ensureDir(context: common.Context): string {
    const dir = `${context.filesDir}/custom_covers`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
    return dir;
  }

  // 清掉该漫画旧的自定义封面（扩展名可能不同）
  private static purge(dir: string, mangaId: number): void {
    const prefix = `${mangaId}.`;
    const names = fs.listFileSync(dir);
    for (let i = 0; i < names.length; i++) {
      if (names[i].lastIndexOf(prefix, 0) === 0) {
        fs.unlinkSync(`${dir}/${names[i]}`);
      }
    }
  }
}
