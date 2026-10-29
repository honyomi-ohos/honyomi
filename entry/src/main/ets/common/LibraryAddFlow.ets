// 共享入库流程（对齐 Mihon MangaViewModel.changeFavorite 的入库分支）：
// 查重提示 / 默认分类偏好分流 / 提交入库（标记 + 多分类 + 封面持久化 + 刷书架 + toast）。
// 弹窗交互留在各页面（CustomDialogController 需组件上下文），此处承担可共享的纯逻辑
import { UIContext } from '@kit.ArkUI';
import { CategoryRecord, MangaRecord } from '../model/Models';
import { MangaRepo } from '../data/Repos';
import { CoverStore } from './CoverStore';
import { Util } from './Util';
import { AppKeys } from './AppKeys';

export class LibraryAddFlow {
  // 默认归入分类偏好分流（对齐 MangaViewModel.kt:366-387）：
  // 返回 null 表示需弹 ChangeCategoryDialog 询问；返回空数组表示按默认逻辑自动入库
  static resolveDefaultCategoryIds(categories: CategoryRecord[], defaultCategory: number): number[] | null {
    if (defaultCategory > 0) {
      const exists: boolean =
        categories.some((c: CategoryRecord): boolean => c.id === defaultCategory);
      return exists ? [defaultCategory] : null;
    }
    // 0 = 自动（Default）：不写 membership，走 setInLibrary 的内容类型默认分类
    if (defaultCategory === 0) {
      return [];
    }
    // -1 = 每次都询问
    return null;
  }

  // 入库提交：标记在库 → 多分类覆盖（ids 非空时）→ 封面持久化 → 刷书架 → toast
  static async commit(ui: UIContext, manga: MangaRecord, categoryIds: number[]): Promise<void> {
    await MangaRepo.setInLibrary(manga.id, true);
    if (categoryIds.length > 0) {
      await MangaRepo.setCategories(manga.id, categoryIds);
    }
    AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
    // 入库即持久化封面（fire-and-forget），完成后再次写 libDirty 刷新书架显示
    LibraryAddFlow.persistCover(ui, manga);
    Util.toastRes(ui, $r('app.string.detail_added_to_library'));
  }

  // 封面持久化（fire-and-forget）：完成后再写 libDirty 刷新书架显示
  static async persistCover(ui: UIContext, manga: MangaRecord): Promise<void> {
    try {
      const url: string = manga.origThumbnail !== '' ? manga.origThumbnail : manga.thumbnailUrl;
      if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
        return;
      }
      const context = Util.hostAbilityContext(ui);
      const path = await CoverStore.persistFromUrl(context, manga.id, url, manga.sourceKey);
      if (path === '') {
        return;
      }
      await MangaRepo.setLocalCover(manga.id, path, url);
      AppStorage.setOrCreate(AppKeys.LIB_DIRTY, (AppStorage.get<number>(AppKeys.LIB_DIRTY) ?? 0) + 1);
    } catch (_e) {
      // 持久化失败不阻塞入库，书架回退在线封面路径
    }
  }

  // 空分类守卫（空 selection 归一回退分类 1，避免 membership 全空）
  static normalizeCategoryIds(ids: number[]): number[] {
    return ids.length > 0 ? ids : [1];
  }
}
