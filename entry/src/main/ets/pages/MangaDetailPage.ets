import { common, Want } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { formProvider, formInfo } from '@kit.FormKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, TrackRepo, CategoryRepo } from '../data/Repos';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord, TrackRecord, DownloadTask, ALMediaItem, CategoryRecord, ContentType } from '../model/Models';
import { DetailParams, GlobalSearchParams } from '../model/RouteParams';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { CoverStore } from '../common/CoverStore';
import { ChapterFlags } from '../common/ChapterFlags';
import { NaturalCompare } from '../common/NaturalCompare';
import { DownloadService } from '../data/DownloadService';
import { WidgetUpdater } from '../form/WidgetUpdater';
import { AniListTracker } from '../data/AniListTracker';
import { InputDialog, ConfirmDialog, CategoryDialog } from './components/Dialogs';
import { SmartImage } from './components/SmartImage';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';
import { CoverViewer } from './components/CoverViewer';
import { CoverPlaceholder } from './components/CoverPlaceholder';
import { ChapterSettingsSheet } from './components/ChapterSettingsSheet';

// 章节行：自订阅 DownloadService 变化刷新下载指示器，
// 避免 ForEach key 携带全局版本号导致整个章节列表重建
@Component
struct DetailChapterRow {
  @Prop chapter: ChapterRecord = new ChapterRecord();
  @Prop isLocalSource: boolean = false;
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State downloaded: boolean = false;
  @State queued: boolean = false;
  @State downloading: boolean = false;
  @State dlPct: number = 0;
  onTap: (chapter: ChapterRecord) => void = (_c: ChapterRecord) => {
  };
  onLongPress: (chapter: ChapterRecord) => void = (_c: ChapterRecord) => {
  };
  // 指示器点击：state 为行内当前下载状态（none/downloading/queued/downloaded）
  onIndicatorTap: (chapter: ChapterRecord, state: string) => void = (_c: ChapterRecord, _s: string) => {
  };
  private onDlNotify = (): void => {
    this.refreshDlState();
  };

  aboutToAppear(): void {
    this.refreshDlState();
    DownloadService.addListener(this.onDlNotify);
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onDlNotify);
  }

  private refreshDlState(): void {
    const d = DownloadService.isDownloaded(this.chapter.id);
    const q = !d && DownloadService.isQueued(this.chapter.id);
    let downloading = false;
    let dlPct = 0;
    if (q) {
      const task = DownloadService.getQueue().find((t: DownloadTask): boolean => t.chapterId === this.chapter.id);
      if (task !== undefined && task.state === 1 && task.total > 0) {
        downloading = true;
        dlPct = Math.round(task.progress * 100 / task.total);
      }
    }
    if (d !== this.downloaded || q !== this.queued || downloading !== this.downloading || dlPct !== this.dlPct) {
      this.downloaded = d;
      this.queued = q;
      this.downloading = downloading;
      this.dlPct = dlPct;
    }
  }

  private dlState(): string {
    if (this.downloaded) {
      return 'downloaded';
    }
    if (this.downloading) {
      return 'downloading';
    }
    if (this.queued) {
      return 'queued';
    }
    return 'none';
  }

  build() {
    Row() {
      if (this.selectionMode) {
        AppIcon({
          name: this.selected ? 'check_box' : 'check_box_outline_blank',
          iconSize: 22,
          tint: this.selected ? this.pal.primary : this.pal.sub
        })
          .margin({ right: 10 })
      }
      Column({ space: 3 }) {
        Row({ space: 5 }) {
          // 未读圆点（对齐 Mihon MangaChapterListItem）
          if (!this.chapter.read) {
            Circle()
              .width(6)
              .height(6)
              .fill(this.pal.primary)
          }
          Text(this.chapter.name)
            .fontSize(14)
            .fontColor(this.chapter.read ? this.pal.sub : this.pal.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.chapter.bookmark) {
            AppIcon({ name: 'bookmark_filled', iconSize: 14, tint: this.pal.primary })
          }
        }
        .width('100%')

        Text(Util.formatDate(this.chapter.dateUpload))
          .fontSize(11)
          .fontColor(this.pal.sub)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 下载指示器（对齐 Mihon ChapterDownloadIndicator）：未下载/进度环/排队/已下载
      if (!this.isLocalSource) {
        Row() {
          if (this.downloaded) {
            AppIcon({ name: 'check_circle', iconSize: 20, tint: this.pal.sub })
          } else if (this.downloading) {
            Progress({ value: this.dlPct, total: 100, type: ProgressType.Ring })
              .width(18)
              .height(18)
              .color(this.pal.sub)
              .style({ strokeWidth: 2 })
          } else if (this.queued) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(this.pal.sub)
          } else {
            AppIcon({ name: 'download', iconSize: 20, tint: this.pal.sub })
          }
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.End)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.onIndicatorTap(this.chapter, this.dlState());
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      this.onTap(this.chapter);
    })
    .gesture(LongPressGesture({ repeat: false })
      .onAction(() => {
        this.onLongPress(this.chapter);
      }))
  }
}

// LazyForEach 数据源：章节列表展示结果缓存变化时 onDataReloaded 通知
class ChapterDataSource implements IDataSource {
  private items: ChapterRecord[] = [];
  private listeners: DataChangeListener[] = [];

  setItems(items: ChapterRecord[]): void {
    this.items = items;
    this.notifyReload();
  }

  notifyReload(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ChapterRecord {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }
}

// 漫画详情页：整页滚动（头部随上滑收起）+ 下拉刷新全量更新章节 + 收藏 + 下载 + AniList 追踪
@Component
export struct MangaDetailPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapters: ChapterRecord[] = [];
  @State loading: boolean = true;
  @State descExpanded: boolean = false;
  @State syncing: boolean = false;
  @State refreshing: boolean = false;
  @State topBarProgress: number = 0;
  @State track: TrackRecord | undefined = undefined;
  @State alResults: ALMediaItem[] = [];
  @State alSearching: boolean = false;
  @State showCoverViewer: boolean = false;
  @State showSettingsSheet: boolean = false;
  // AniList 追踪卡片：默认收起，由操作行"追踪"按钮展开（对齐 Mihon Tracking 按钮拉起追踪面板）
  @State showTrackingCard: boolean = false;
  // 章节排序/筛选状态（持久化于 manga.chapterFlags，对齐 Mihon ChapterSettingsDialog）
  @State @Watch('onFilterStateChanged') sortMode: number = ChapterFlags.SORTING_SOURCE;
  @State @Watch('onFilterStateChanged') sortAscending: boolean = false;
  @State @Watch('onFilterStateChanged') fUnread: string = 'ignore';
  @State @Watch('onFilterStateChanged') fDownloaded: string = 'ignore';
  @State @Watch('onFilterStateChanged') fBookmarked: string = 'ignore';
  // 多选章节 id 集合（非空即处于选择模式）；变化时通知 LazyForEach 重跑行生成器刷新勾选态
  @State @Watch('onSelectedIdsChanged') selectedIds: Set<number> = new Set<number>();
  // 章节列表展示缓存：filter+sort 结果仅在 章节数据/筛选/排序 变化时重算，
  // 滚动（onScroll → syncTopBar）不再触发全量重算
  @State shownChapterCache: ChapterRecord[] = [];
  private mangaId: number = -1;
  private listScroller: Scroller = new Scroller();
  private chapterSource: ChapterDataSource = new ChapterDataSource();
  private alSearchId: number = 0;
  private applyingFlags: boolean = false;

  // fire-and-forget 异步处理器统一包装：捕获异常 + 日志 + toast，替代裸调用
  private runSafe(fn: () => Promise<void>): void {
    fn().catch((e: Error) => {
      const msg = e instanceof Error ? e.message : `${e}`;
      hilog.warn(0x0001, 'MangaDetail', 'async handler failed: %{public}s', msg);
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    });
  }

  // 下载完成/删除影响"已下载"筛选结果时重算展示缓存
  private onDlNotify = (): void => {
    if (this.fDownloaded !== 'ignore') {
      this.rebuildShownChapters();
    }
  };

  // ----- 头部信息（对齐 Mihon MangaContentInfo） -----

  // 源显示名：内置本地源走本地化资源，其余取插件名
  private sourceDisplayName(): string {
    const source = SourceRegistry.get(this.manga.sourceKey);
    if (source === undefined) {
      return this.manga.sourceKey;
    }
    return Util.localSourceName(this.getUIContext(), this.manga.sourceKey, source.name);
  }

  // 状态图标（对齐 Mihon MangaContentInfo 状态图标映射）
  private statusIconName(): string {
    switch (this.manga.status) {
      case 'ongoing':
        return 'schedule';
      case 'completed':
        return 'done_all';
      case 'licensed':
        return 'public';
      case 'hiatus':
        return 'pause';
      case 'cancelled':
        return 'close';
      case 'publication_complete':
        return 'done';
      default:
        return 'info';
    }
  }

  // 标签列表：genre 逗号分隔字符串 → 标签数组（对齐 Mihon tags chips）
  private tagList(): string[] {
    return this.manga.genre
      .split(',')
      .map((s: string): string => s.trim())
      .filter((s: string): boolean => s !== '');
  }

  // 全局搜索跳转（标题/作者/标签点击，对齐 Mihon doSearch(query, global=true)）
  private searchGlobal(query: string): void {
    const params: GlobalSearchParams = { query: query };
    this.pathStack.pushPathByName('GlobalSearch', params);
  }

  // 复制标签到剪贴板（对齐 Mihon onCopyTagToClipboard）
  private copyTag(tag: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, tag);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_tag_copied'));
    }).catch((_e: BusinessError) => {
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    });
  }

  // 章节行下载指示器点击（对齐 Mihon ChapterDownloadIndicator 交互）：
  // 未下载→入队；下载中/排队→取消；已下载→确认后删除
  private onChapterIndicatorTap(chapter: ChapterRecord, state: string): void {
    if (state === 'downloaded') {
      const dialog = new CustomDialogController({
        builder: ConfirmDialog({
          title: $r('app.string.detail_dl_delete_confirm'),
          message: chapter.name,
          confirmText: $r('app.string.common_delete'),
          onConfirm: (): void => {
            dialog.close();
            this.runSafe((): Promise<void> => this.deleteChapterDownload(chapter));
          },
          onClose: (): void => {
            dialog.close();
          },
        }),
        autoCancel: true,
      });
      dialog.open();
    } else if (state === 'downloading' || state === 'queued') {
      DownloadService.cancel(chapter.id);
      Util.toastRes(this.getUIContext(), $r('app.string.detail_dl_cancelled'));
    } else {
      this.runSafe((): Promise<void> => this.downloadChapter(chapter));
    }
  }

  private async deleteChapterDownload(chapter: ChapterRecord): Promise<void> {
    await DownloadService.deleteChapter(this.mangaId, chapter.id);
    Util.toastRes(this.getUIContext(), $r('app.string.detail_dl_deleted_one'));
  }

  aboutToAppear(): void {
    DownloadService.addListener(this.onDlNotify);
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onDlNotify);
  }

  onLibDirty(): void {
    this.runSafe((): Promise<void> => this.reloadLocal());
  }

  private async loadAll(): Promise<void> {
    try {
      await this.syncFromSource();
      this.track = await TrackRepo.get(this.mangaId);
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      hilog.warn(0x0001, 'MangaDetail', 'loadAll failed: %{public}s', msg);
      Util.toastRes(this.getUIContext(), $r('app.string.detail_load_failed'));
    } finally {
      this.loading = false;
    }
  }

  private async reloadLocal(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    const record = await MangaRepo.get(this.mangaId);
    if (record !== undefined) {
      this.manga = record;
      this.applyChapterFlags();
    }
    this.chapters = await ChapterRepo.listByManga(this.mangaId);
    this.rebuildShownChapters();
    this.loading = false;
  }

  private async syncFromSource(): Promise<void> {
    if (this.syncing) {
      // 下拉刷新在同步进行中时明确提示，而不是静默失效
      Util.toastRes(this.getUIContext(), $r('app.string.detail_sync_in_progress'));
      return;
    }
    this.syncing = true;
    try {
      if (this.manga.id !== this.mangaId) {
        // 首次进入：先载入本地数据（取 sourceKey/url）再同步
        await this.reloadLocal();
      }
      const source = SourceRegistry.get(this.manga.sourceKey);
      if (source !== undefined) {
        try {
          const chapters = await source.getChapterList(this.manga.url);
          await ChapterRepo.syncFromSource(this.mangaId, chapters);
          const detail = await source.getMangaDetail(this.manga.url);
          await MangaRepo.upsertFromSource(this.manga.sourceKey, detail, source.contentType);
        } catch (e) {
          Util.toastRes(this.getUIContext(), $r('app.string.detail_sync_failed_local'));
        }
        await this.reloadLocal();
      }
    } finally {
      this.syncing = false;
    }
  }

  // 下拉刷新：全量重新同步源数据（含源端已删除章节的移除）
  private async refreshFromSource(): Promise<void> {
    try {
      await this.syncFromSource();
    } finally {
      this.refreshing = false;
    }
  }

  // 排序/筛选状态变化（弹层回调或本地数据应用）时重算展示缓存
  private onFilterStateChanged(): void {
    if (!this.applyingFlags) {
      this.rebuildShownChapters();
    }
  }

  // 多选集合变化：通知 LazyForEach 重跑行生成器，刷新勾选框与选择模式角标
  private onSelectedIdsChanged(): void {
    this.chapterSource.notifyReload();
  }

  // 重算 filter+sort 展示缓存并推给 LazyForEach 数据源
  private rebuildShownChapters(): void {
    this.shownChapterCache = this.shownChapters();
    this.chapterSource.setItems(this.shownChapterCache);
  }

  // 头部总高度：保证封面信息在任意状态栏高度下完整展示
  private headerHeight(): number {
    return Math.max(280, this.statusBarH + 236);
  }

  // 吸顶栏渐显进度：随滚动偏移 0 → 1
  private syncTopBar(): void {
    const y = this.listScroller.currentOffset().yOffset;
    const p = Math.min(1, Math.max(0, y / 180));
    if (p !== this.topBarProgress) {
      this.topBarProgress = p;
    }
  }

  // 从持久化标志位解码排序/筛选状态（对齐 Mihon Manga.chapterFlags 解码）
  // applyingFlags 标志避免批量赋值触发多次重算，由调用方统一 rebuild
  private applyChapterFlags(): void {
    this.applyingFlags = true;
    const flags = this.manga.chapterFlags;
    this.sortMode = ChapterFlags.sortingMode(flags);
    this.sortAscending = ChapterFlags.isAscending(flags);
    this.fUnread = ChapterFlags.unreadFilter(flags);
    this.fDownloaded = ChapterFlags.downloadedFilter(flags);
    this.fBookmarked = ChapterFlags.bookmarkedFilter(flags);
    this.applyingFlags = false;
  }

  // 当前状态编码回标志位并持久化
  private async persistChapterFlags(): Promise<void> {
    const flags = ChapterFlags.encode(this.sortMode, this.sortAscending,
      this.fUnread, this.fDownloaded, this.fBookmarked);
    if (flags === this.manga.chapterFlags) {
      return;
    }
    this.manga.chapterFlags = flags;
    await MangaRepo.setChapterFlags(this.mangaId, flags);
  }

  // 是否有筛选生效（头部图标着色提示）
  private filterActive(): boolean {
    return this.fUnread !== 'ignore' || this.fDownloaded !== 'ignore' || this.fBookmarked !== 'ignore';
  }

  // 展示顺序：先按三态筛选过滤（对齐 Mihon applyFilters），再按排序模式/方向排序。
  // 本地源 sortOrder 已按自然顺序（含中文数字）生成，"按源顺序"即为真实章节顺序；
  // 线上源保持源返回顺序
  private shownChapters(): ChapterRecord[] {
    const isLocal = ContentType.isLocal(this.manga.sourceKey);
    let list = this.chapters;
    if (this.filterActive()) {
      list = list.filter((c: ChapterRecord): boolean => {
        if (this.fUnread === 'include' && c.read) {
          return false;
        }
        if (this.fUnread === 'exclude' && !c.read) {
          return false;
        }
        if (this.fBookmarked === 'include' && !c.bookmark) {
          return false;
        }
        if (this.fBookmarked === 'exclude' && c.bookmark) {
          return false;
        }
        if (this.fDownloaded !== 'ignore') {
          const downloaded = isLocal || DownloadService.isDownloaded(c.id);
          if (this.fDownloaded === 'include' && !downloaded) {
            return false;
          }
          if (this.fDownloaded === 'exclude' && downloaded) {
            return false;
          }
        }
        return true;
      });
    }
    const sorted = list.slice().sort((a: ChapterRecord, b: ChapterRecord): number => {
      return this.compareChapters(a, b);
    });
    // 方向：倒序 = 源顺序原样（线上源即返回顺序），正序 = 反向（对齐 Mihon sortDescending 语义）
    return this.sortAscending ? sorted.reverse() : sorted;
  }

  // 排序比较器（对齐 Mihon getChapterSort），同值回退 sortOrder/id 保证稳定
  private compareChapters(a: ChapterRecord, b: ChapterRecord): number {
    let cmp = 0;
    if (this.sortMode === ChapterFlags.SORTING_NUMBER) {
      cmp = a.chapterNumber - b.chapterNumber;
    } else if (this.sortMode === ChapterFlags.SORTING_UPLOAD_DATE) {
      cmp = a.dateUpload - b.dateUpload;
    } else if (this.sortMode === ChapterFlags.SORTING_ALPHABET) {
      cmp = NaturalCompare.compare(a.name, b.name);
    }
    if (cmp !== 0) {
      return cmp;
    }
    if (a.sortOrder !== b.sortOrder) {
      return a.sortOrder - b.sortOrder;
    }
    return a.id - b.id;
  }

  private async toggleLibrary(): Promise<void> {
    if (this.manga.inLibrary) {
      // 移出书架：直接执行
      await MangaRepo.setInLibrary(this.manga.id, false);
      AppStorage.set('libDirty', this.libDirty + 1);
      Util.toastRes(this.getUIContext(), $r('app.string.detail_removed_from_library'));
      return;
    }
    // 加入书架：存在用户自建（非默认）分类时，先弹分类选择，确定后再入库
    const context = Util.hostAbilityContext(this.getUIContext());
    await AppDb.ready(context);
    const categories: CategoryRecord[] = await CategoryRepo.list();
    const hasCustom = categories.some((c: CategoryRecord): boolean => !ContentType.isBuiltinCategory(c.name));
    if (hasCustom) {
      this.showAddCategoryDialog(categories);
      return;
    }
    await this.addToLibrary(-1);
  }

  // 入库（categoryId >= 0 时覆盖默认分类），只写 libDirty 由 @Watch 统一刷新书架
  private async addToLibrary(categoryId: number): Promise<void> {
    await MangaRepo.setInLibrary(this.manga.id, true);
    if (categoryId >= 0) {
      await MangaRepo.setCategory(this.manga.id, categoryId);
    }
    AppStorage.set('libDirty', this.libDirty + 1);
    // 入库即持久化封面（AVIF 经图片管线转码为 JPEG 落盘），书架离线可显、无插件注册竞态
    this.persistCover();
    Util.toastRes(this.getUIContext(), $r('app.string.detail_added_to_library'));
  }

  // 入库前分类选择弹窗（存在非默认分类时），选中分类即确认入库
  private showAddCategoryDialog(categories: CategoryRecord[]): void {
    const dialog = new CustomDialogController({
      builder: CategoryDialog({
        categories: categories,
        onPick: (categoryId: number): void => {
          this.runSafe((): Promise<void> => this.addToLibrary(categoryId));
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  // 封面持久化（fire-and-forget）：完成后再写 libDirty 刷新书架显示
  private async persistCover(): Promise<void> {
    try {
      const url = this.manga.origThumbnail !== '' ? this.manga.origThumbnail : this.manga.thumbnailUrl;
      if (url.indexOf('http://') !== 0 && url.indexOf('https://') !== 0) {
        return;
      }
      const context = Util.hostAbilityContext(this.getUIContext());
      const path = await CoverStore.persistFromUrl(context, this.manga.id, url, this.manga.sourceKey);
      if (path === '') {
        return;
      }
      await MangaRepo.setLocalCover(this.manga.id, path, url);
      AppStorage.set('libDirty', this.libDirty + 1);
    } catch (_e) {
      // 持久化失败不阻塞入库，书架回退在线封面路径
    }
  }

  // 更换封面（对齐 Mihon Edit cover）：系统图库选图 → 复制为自定义封面 → 详情/书架同步生效
  private async editCover(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1,
      });
      const uris = result.photoUris;
      if (uris.length === 0) {
        return;
      }
      const context = Util.hostAbilityContext(this.getUIContext());
      const coverPath = await CoverStore.save(context, this.mangaId, uris[0]);
      if (coverPath === '') {
        Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_save_failed'));
        return;
      }
      await MangaRepo.applyCustomCover(this.mangaId, coverPath);
      AppStorage.set('libDirty', this.libDirty + 1);
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_updated'));
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_save_failed'));
    }
  }

  // 恢复原封面（对齐 Mihon Reset cover）：删除自定义封面文件，回退到源封面地址
  private async resetCover(): Promise<void> {
    const context = Util.hostAbilityContext(this.getUIContext());
    CoverStore.remove(context, this.mangaId);
    await MangaRepo.resetCover(this.mangaId);
    AppStorage.set('libDirty', this.libDirty + 1);
    Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_reset'));
  }

  // 标签 chip（对齐 Mihon TagsChip）：点击跳全局搜索，长按复制
  @Builder
  TagChip(tag: string) {
    Text(tag)
      .fontSize(12)
      .fontColor(this.pal.text)
      .backgroundColor(this.pal.chip)
      .borderRadius(14)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .margin({ right: 6, top: 6 })
      .onClick(() => {
        this.searchGlobal(tag);
      })
      .gesture(LongPressGesture({ repeat: false })
        .onAction(() => {
          this.copyTag(tag);
        }))
  }

  // 封面查看器（对齐 Mihon MangaCoverDialog）：点击封面进入全屏查看，
  // 底部提供关闭/分享/保存/编辑封面，编辑含恢复原封面入口
  @Builder
  coverViewerBuilder() {
    CoverViewer({
      coverUrl: this.manga.thumbnailUrl,
      sourceKey: this.manga.sourceKey,
      isCustom: this.manga.origThumbnail !== '',
      title: this.manga.title,
      onClose: (): void => {
        this.showCoverViewer = false;
      },
      onEdit: (): void => {
        this.runSafe((): Promise<void> => this.editCover());
      },
      onDelete: (): void => {
        this.runSafe((): Promise<void> => this.resetCover());
      },
    })
  }

  // 续读章节：基于用户排序/筛选后的展示顺序（缓存结果），而非 DB 原始顺序
  private continueChapter(): ChapterRecord | undefined {
    const shown = this.shownChapterCache;
    if (shown.length === 0) {
      return undefined;
    }
    for (const chapter of shown) {
      if (!chapter.read) {
        return chapter;
      }
    }
    return shown[shown.length - 1];
  }

  private openReader(chapterId: number): void {
    ContentOpen.push(this.pathStack, this.manga.contentType, this.mangaId, chapterId);
  }

  private actionLabel(): Resource {
    if (this.continueChapter() === undefined) {
      return $r('app.string.detail_no_chapters_yet');
    }
    const started = this.chapters.some((c: ChapterRecord): boolean => c.read);
    if (this.manga.contentType === ContentType.VIDEO) {
      return started ? $r('app.string.detail_continue_playing') : $r('app.string.detail_start_playing');
    }
    return started ? $r('app.string.detail_continue_reading') : $r('app.string.detail_start_reading');
  }

  // 添加漫画卡片到桌面：先写 pending mangaId（openFormManager 不携带自定义参数），再打开系统卡片管理页
  private addToDesktop(): void {
    const context = Util.hostAbilityContext(this.getUIContext());
    WidgetUpdater.setPendingManga(context, this.mangaId).then((): void => {
      const params: Record<string, Object> = {};
      params[formInfo.FormParam.NAME_KEY] = 'MangaCard';
      params[formInfo.FormParam.MODULE_NAME_KEY] = 'entry';
      params[formInfo.FormParam.DIMENSION_KEY] = formInfo.FormDimension.Dimension_2_2;
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryFormAbility',
        parameters: params
      };
      try {
        formProvider.openFormManager(want);
      } catch (e) {
        Util.toastRes(this.getUIContext(), $r('app.string.detail_card_add_failed'));
      }
    }).catch((_e: Error) => {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_card_add_failed'));
    });
  }

  private async markAllRead(): Promise<void> {
    await ChapterRepo.markAllRead(this.mangaId, true);
    AppStorage.set('libDirty', this.libDirty + 1);
    Util.toastRes(this.getUIContext(), $r('app.string.detail_all_marked_read'));
  }

  // 单章入队校验（视频源先检查是否有直链可下载）
  // 返回：'ok' 已入队 | 'no_direct' 仅流媒体无直链 | 'failed' 校验/入队失败
  private async enqueueDownload(chapter: ChapterRecord): Promise<string> {
    if (ContentType.isLocal(this.manga.sourceKey)) {
      return 'failed';
    }
    if (this.manga.contentType === ContentType.VIDEO) {
      const source = SourceRegistry.get(this.manga.sourceKey);
      if (source === undefined) {
        return 'failed';
      }
      try {
        const videos = await source.getVideoList(chapter.url);
        let direct = false;
        for (let i = 0; i < videos.length; i++) {
          if (!ContentType.isPlaylist(videos[i].url)) {
            direct = true;
            break;
          }
        }
        if (!direct) {
          return 'no_direct';
        }
      } catch (_e) {
        return 'failed';
      }
    }
    const task = new DownloadTask();
    task.mangaId = this.mangaId;
    task.mangaTitle = this.manga.title;
    task.chapterId = chapter.id;
    task.chapterName = chapter.name;
    task.sourceKey = this.manga.sourceKey;
    task.mangaUrl = this.manga.url;
    task.chapterUrl = chapter.url;
    DownloadService.enqueue(task);
    return 'ok';
  }

  private async downloadChapter(chapter: ChapterRecord): Promise<void> {
    if (ContentType.isLocal(this.manga.sourceKey)) {
      return;
    }
    const status = await this.enqueueDownload(chapter);
    if (status === 'ok') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_queued'));
    } else if (status === 'no_direct') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_stream_only'));
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_failed'));
    }
  }

  // 批量入队（多选下载 / 下载菜单）：两个 worker 共享递增游标实现 2 并发，
  // 完成后统一提示入队数量；视频源批量需逐章请求解析接口，先提示准备中
  private async downloadChapters(list: ChapterRecord[]): Promise<void> {
    if (ContentType.isLocal(this.manga.sourceKey) || list.length === 0) {
      return;
    }
    if (this.manga.contentType === ContentType.VIDEO) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_dl_preparing'));
    }
    let index = 0;
    let count = 0;
    const worker = async (): Promise<void> => {
      while (index < list.length) {
        const chapter = list[index];
        index += 1;
        const status = await this.enqueueDownload(chapter);
        if (status === 'ok') {
          count += 1;
        }
      }
    };
    await Promise.all([worker(), worker()]);
    if (count > 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_dl_queued_n'), [count]);
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_stream_only'));
    }
  }

  // 下载菜单动作（对齐 Mihon DownloadAction）：count>0 取展示顺序前 N 个未读，
  // count=-1 全部未读，count=-2 全部书签
  private downloadAction(count: number): void {
    if (ContentType.isLocal(this.manga.sourceKey)) {
      return;
    }
    let list: ChapterRecord[] = [];
    if (count === -2) {
      list = this.chapters.filter((c: ChapterRecord): boolean => c.bookmark);
    } else {
      const unread = this.shownChapterCache.filter((c: ChapterRecord): boolean => !c.read);
      list = count > 0 ? unread.slice(0, count) : unread;
    }
    if (list.length === 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_no_unread'));
      return;
    }
    this.runSafe((): Promise<void> => this.downloadChapters(list));
  }

  // ----- 多选操作（对齐 Mihon 章节多选底部动作菜单） -----

  private toggleSelected(chapterId: number): void {
    const next = new Set<number>(this.selectedIds);
    if (next.has(chapterId)) {
      next.delete(chapterId);
    } else {
      next.add(chapterId);
    }
    this.selectedIds = next;
  }

  private clearSelection(): void {
    this.selectedIds = new Set<number>();
  }

  // 全选/取消全选（针对当前展示顺序的全部章节）
  private toggleSelectAll(): void {
    const shown = this.shownChapterCache;
    let allSelected = true;
    for (const c of shown) {
      if (!this.selectedIds.has(c.id)) {
        allSelected = false;
        break;
      }
    }
    if (allSelected) {
      this.clearSelection();
      return;
    }
    const next = new Set<number>(this.selectedIds);
    for (const c of shown) {
      next.add(c.id);
    }
    this.selectedIds = next;
  }

  private selectedChapters(): ChapterRecord[] {
    return this.chapters.filter((c: ChapterRecord): boolean => this.selectedIds.has(c.id));
  }

  private async markSelectedRead(read: boolean): Promise<void> {
    const ids = Array.from(this.selectedIds);
    if (ids.length === 0) {
      return;
    }
    await ChapterRepo.setReadForIds(ids, read);
    AppStorage.set('libDirty', this.libDirty + 1);
    this.clearSelection();
  }

  // 书签切换：全部已书签则移除，否则添加（对齐 Mihon 底部菜单 Bookmark/Remove bookmark）
  private async toggleSelectedBookmark(): Promise<void> {
    const selected = this.selectedChapters();
    if (selected.length === 0) {
      return;
    }
    let allBookmarked = true;
    for (const c of selected) {
      if (!c.bookmark) {
        allBookmarked = false;
        break;
      }
    }
    const ids = Array.from(this.selectedIds);
    await ChapterRepo.setBookmarkForIds(ids, !allBookmarked);
    // 书签影响展示筛选结果，写 libDirty 统一触发 reloadLocal 重算展示缓存
    AppStorage.set('libDirty', this.libDirty + 1);
    this.clearSelection();
  }

  private async downloadSelected(): Promise<void> {
    const selected = this.selectedChapters();
    this.clearSelection();
    await this.downloadChapters(selected);
  }

  // 删除所选章节的下载（仅线上源；队列中未完成的任务一并取消）
  private deleteSelectedDownloads(): void {
    let count = 0;
    for (const c of this.selectedChapters()) {
      if (DownloadService.isDownloaded(c.id)) {
        this.runSafe((): Promise<void> => DownloadService.deleteChapter(this.mangaId, c.id));
        count += 1;
      }
    }
    if (count > 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_deleted_n'), [count]);
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_no_downloads'));
    }
    this.clearSelection();
  }

  private showAlSearch(): void {
    if (Settings.getAnilistToken() === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_config_anilist_token'));
      return;
    }
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.detail_search_anilist'),
        placeholder: $r('app.string.detail_manga_title_hint'),
        onConfirm: (text: string): void => {
          this.runSafe((): Promise<void> => this.doAlSearch(text));
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async doAlSearch(query: string): Promise<void> {
    const q = query.trim();
    if (q === '') {
      return;
    }
    const token = Settings.getAnilistToken();
    this.alSearching = true;
    try {
      this.alResults = await AniListTracker.search(q, token, this.manga.contentType);
      if (this.alResults.length === 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.detail_no_search_results'));
      }
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_anilist_search_failed'));
    }
    this.alSearching = false;
  }

  private async bindAl(item: ALMediaItem): Promise<void> {
    await TrackRepo.bind(this.mangaId, item.id, item.title);
    this.track = await TrackRepo.get(this.mangaId);
    this.alResults = [];
    Util.toastRes(this.getUIContext(), $r('app.string.detail_anilist_bound'));
  }

  private async unbindAl(): Promise<void> {
    await TrackRepo.unbind(this.mangaId);
    this.track = undefined;
    this.alResults = [];
    Util.toastRes(this.getUIContext(), $r('app.string.detail_anilist_unbound'));
  }

  private async syncTrack(): Promise<void> {
    if (this.track === undefined) {
      return;
    }
    const token = Settings.getAnilistToken();
    if (token === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_config_anilist_token'));
      return;
    }
    let progress = 0;
    for (const c of this.chapters) {
      if (c.read && c.chapterNumber > progress) {
        progress = Math.floor(c.chapterNumber);
      }
    }
    try {
      await AniListTracker.updateProgress(token, this.track.remoteId, progress);
      await TrackRepo.setLastChapterRead(this.mangaId, progress);
      this.track = await TrackRepo.get(this.mangaId);
      Util.toastRes(this.getUIContext(), $r('app.string.detail_synced_progress'), [progress]);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_anilist_sync_failed'));
    }
  }

  // 章节排序/筛选设置弹层（对齐 Mihon ChapterSettingsDialog）
  @Builder
  chapterSettingsSheetBuilder() {
    ChapterSettingsSheet({
      initSortMode: this.sortMode,
      initAscending: this.sortAscending,
      initUnread: this.fUnread,
      initDownloaded: this.fDownloaded,
      initBookmarked: this.fBookmarked,
      onSortChanged: (mode: number, ascending: boolean): void => {
        this.sortMode = mode;
        this.sortAscending = ascending;
        this.runSafe((): Promise<void> => this.persistChapterFlags());
      },
      onFilterChanged: (unread: string, downloaded: string, bookmarked: string): void => {
        this.fUnread = unread;
        this.fDownloaded = downloaded;
        this.fBookmarked = bookmarked;
        this.runSafe((): Promise<void> => this.persistChapterFlags());
      }
    })
  }

  // 批量下载菜单（对齐 Mihon DownloadAction）
  @Builder
  bulkDownloadMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.detail_dl_next_n', 1) })
        .onClick(() => {
          this.downloadAction(1);
        })
      MenuItem({ content: $r('app.string.detail_dl_next_n', 5) })
        .onClick(() => {
          this.downloadAction(5);
        })
      MenuItem({ content: $r('app.string.detail_dl_next_n', 10) })
        .onClick(() => {
          this.downloadAction(10);
        })
      MenuItem({ content: $r('app.string.detail_dl_next_n', 25) })
        .onClick(() => {
          this.downloadAction(25);
        })
      MenuItem({ content: $r('app.string.detail_dl_unread') })
        .onClick(() => {
          this.downloadAction(-1);
        })
      MenuItem({ content: $r('app.string.detail_dl_bookmarked') })
        .onClick(() => {
          this.downloadAction(-2);
        })
    }
  }

  // 多选底部动作条（对齐 Mihon SharedMangaBottomActionMenu）
  @Builder
  selectionActionBar() {
    Column() {
      Row() {
        AppIcon({ name: 'close', iconSize: 22, tint: this.pal.text })
          .width(40)
          .height(40)
          .onClick(() => {
            this.clearSelection();
          })
        Text($r('app.string.detail_selected_count', this.selectedIds.size))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        AppIcon({ name: 'select_all', iconSize: 22, tint: this.pal.text })
          .width(40)
          .height(40)
          .onClick(() => {
            this.toggleSelectAll();
          })
      }
      .width('100%')
      Row() {
        Column({ space: 4 }) {
          AppIcon({ name: 'done_all', iconSize: 22, tint: this.pal.text })
          Text($r('app.string.detail_action_mark_read'))
            .fontSize(11)
            .fontColor(this.pal.text)
        }
        .onClick(() => {
          this.runSafe((): Promise<void> => this.markSelectedRead(true));
        })

        Column({ space: 4 }) {
          AppIcon({ name: 'done', iconSize: 22, tint: this.pal.text })
          Text($r('app.string.detail_action_mark_unread'))
            .fontSize(11)
            .fontColor(this.pal.text)
        }
        .onClick(() => {
          this.runSafe((): Promise<void> => this.markSelectedRead(false));
        })

        Column({ space: 4 }) {
          AppIcon({ name: 'bookmark', iconSize: 22, tint: this.pal.text })
          Text($r('app.string.detail_action_bookmark'))
            .fontSize(11)
            .fontColor(this.pal.text)
        }
        .onClick(() => {
          this.runSafe((): Promise<void> => this.toggleSelectedBookmark());
        })

        if (!ContentType.isLocal(this.manga.sourceKey)) {
          Column({ space: 4 }) {
            AppIcon({ name: 'download', iconSize: 22, tint: this.pal.text })
            Text($r('app.string.detail_download'))
              .fontSize(11)
              .fontColor(this.pal.text)
          }
          .onClick(() => {
            this.runSafe((): Promise<void> => this.downloadSelected());
          })

          Column({ space: 4 }) {
            AppIcon({ name: 'delete', iconSize: 22, tint: this.pal.text })
            Text($r('app.string.detail_action_delete'))
              .fontSize(11)
              .fontColor(this.pal.text)
          }
          .onClick(() => {
            this.deleteSelectedDownloads();
          })
        }
      }
      .width('100%')
      .padding({ top: 6, bottom: 14, left: 20, right: 20 })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
    .backgroundColor(this.pal.card)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          // 整页滚动 + 下拉刷新：头部随列表上滑收起，不再固定占位
          Refresh({ refreshing: $$this.refreshing }) {
          List({ scroller: this.listScroller }) {
            // 头部：封面背景 + 信息
            ListItem() {
              Stack({ alignContent: Alignment.TopStart }) {
                if (this.manga.thumbnailUrl !== '') {
                  SmartImage({ url: this.manga.thumbnailUrl, sourceKey: this.manga.sourceKey, fit: ImageFit.Cover, fill: true })
                    .width('100%')
                    .height(this.headerHeight())
                    .blur(30)
                } else {
                  CoverPlaceholder()
                    .width('100%')
                    .height(this.headerHeight())
                    .blur(30)
                }
                Column()
                  .width('100%')
                  .height(this.headerHeight())
                  .linearGradient({
                    angle: 180,
                    colors: [['#80000000', 0.0], [this.isDark ? '#F0101318' : '#F0F2F3F7', 1.0]],
                  })

                Column() {
                  // 吸顶栏占位（状态栏 + 返回/标题栏高度）
                  Column()
                    .height(this.statusBarH + 52)
                  Row({ space: 14 }) {
                    // 封面：点击进入全屏查看器（对齐 Mihon onCoverClick）
                    Stack() {
                      if (this.manga.thumbnailUrl !== '') {
                        SmartImage({ url: this.manga.thumbnailUrl, sourceKey: this.manga.sourceKey, fit: ImageFit.Cover, fill: true })
                      } else {
                        CoverPlaceholder({ iconSize: 34 })
                      }
                    }
                    .width(110)
                    .height(150)
                    .borderRadius(10)
                    .clip(true)
                    .backgroundColor(this.pal.chip)
                    .onClick(() => {
                      this.showCoverViewer = true;
                    })
                    .bindContentCover($$this.showCoverViewer, this.coverViewerBuilder(), {
                      modalTransition: ModalTransition.ALPHA,
                      backgroundColor: '#B3000000',
                    })
                    // 标题/作者/状态+源名（对齐 Mihon MangaContentInfo）：
                    // 标题、作者点击跳全局搜索；状态行 = 状态图标 + 状态文案 · 源名
                    Column({ space: 5 }) {
                      Text(this.manga.title)
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.pal.text)
                        .maxLines(3)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .onClick(() => {
                          if (this.manga.title.trim() !== '') {
                            this.searchGlobal(this.manga.title.trim());
                          }
                        })
                      if (this.manga.author !== '') {
                        Text(this.manga.author)
                          .fontSize(13)
                          .fontColor(this.pal.sub)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .onClick(() => {
                            this.searchGlobal(this.manga.author);
                          })
                      }
                      Row({ space: 4 }) {
                        AppIcon({
                          name: this.statusIconName(),
                          iconSize: 15,
                          tint: this.pal.primary
                        })
                        Text(ContentType.isLocal(this.manga.sourceKey) ? $r('app.string.detail_status_local') : Util.statusLabel(this.manga.status))
                          .fontSize(12)
                          .fontColor(this.pal.primary)
                          .maxLines(1)
                        Text('·')
                          .fontSize(12)
                          .fontColor(this.pal.sub)
                        Text(this.sourceDisplayName())
                          .fontSize(12)
                          .fontColor(this.pal.sub)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                      }
                      .width('100%')
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12 })
                  .alignItems(VerticalAlign.Top)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .height(this.headerHeight())
            }

            // 操作按钮行（对齐 Mihon MangaActionRow）：收藏 / 续读 / 追踪 / 桌面卡片
            ListItem() {
              Row() {
                Column({ space: 5 }) {
                  AppIcon({
                    name: 'favorite',
                    iconSize: 22,
                    tint: this.manga.inLibrary ? this.pal.primary : this.pal.sub
                  })
                  Text(this.manga.inLibrary ? $r('app.string.detail_in_library') : $r('app.string.detail_add_to_library'))
                    .fontSize(11)
                    .maxLines(2)
                    .textAlign(TextAlign.Center)
                    .fontColor(this.manga.inLibrary ? this.pal.primary : this.pal.sub)
                }
                .layoutWeight(1)
                .onClick(() => {
                  this.runSafe((): Promise<void> => this.toggleLibrary());
                })

                Column({ space: 5 }) {
                  AppIcon({ name: 'play_arrow', iconSize: 22, tint: this.pal.sub })
                  Text(this.actionLabel())
                    .fontSize(11)
                    .maxLines(2)
                    .textAlign(TextAlign.Center)
                    .fontColor(this.pal.sub)
                }
                .layoutWeight(1)
                .onClick(() => {
                  const chapter = this.continueChapter();
                  if (chapter !== undefined) {
                    this.openReader(chapter.id);
                  }
                })

                Column({ space: 5 }) {
                  AppIcon({
                    name: 'sync',
                    iconSize: 22,
                    tint: this.track !== undefined ? this.pal.primary : this.pal.sub
                  })
                  Text($r('app.string.detail_action_tracking'))
                    .fontSize(11)
                    .maxLines(2)
                    .textAlign(TextAlign.Center)
                    .fontColor(this.track !== undefined ? this.pal.primary : this.pal.sub)
                }
                .layoutWeight(1)
                .onClick(() => {
                  this.showTrackingCard = !this.showTrackingCard;
                })

                if (this.manga.inLibrary) {
                  Column({ space: 5 }) {
                    AppIcon({ name: 'collections_bookmark', iconSize: 22, tint: this.pal.sub })
                    Text($r('app.string.detail_add_to_desktop'))
                      .fontSize(11)
                      .maxLines(2)
                      .textAlign(TextAlign.Center)
                      .fontColor(this.pal.sub)
                  }
                  .layoutWeight(1)
                  .onClick(() => {
                    this.addToDesktop();
                  })
                }
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 14 })
            }

            // 简介 + 标签（对齐 Mihon ExpandableMangaDescription）
            if (this.manga.description !== '' || this.tagList().length > 0) {
              ListItem() {
                Column() {
                  if (this.manga.description !== '') {
                    Text(Util.localDescriptionLabel(this.getUIContext(), this.manga.description))
                      .fontSize(13)
                      .fontColor(this.pal.sub)
                      .maxLines(this.descExpanded ? 999 : 3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    Text(this.descExpanded ? $r('app.string.detail_collapse') : $r('app.string.detail_expand'))
                      .fontSize(12)
                      .fontColor(this.pal.primary)
                      .margin({ top: 4 })
                      .onClick(() => {
                        this.descExpanded = !this.descExpanded;
                      })
                  }
                  // 标签：展开时流式换行，收起时单行横向滚动（对齐 Mihon tags chips）
                  if (this.tagList().length > 0) {
                    if (this.descExpanded) {
                      Flex({ wrap: FlexWrap.Wrap }) {
                        ForEach(this.tagList(), (tag: string) => {
                          this.TagChip(tag)
                        }, (tag: string, idx: number) => `tag-${idx}-${tag}`)
                      }
                    } else {
                      Scroll() {
                        Row() {
                          ForEach(this.tagList(), (tag: string) => {
                            this.TagChip(tag)
                          }, (tag: string, idx: number) => `tag-${idx}-${tag}`)
                        }
                      }
                      .scrollable(ScrollDirection.Horizontal)
                      .scrollBar(BarState.Off)
                      .edgeEffect(EdgeEffect.None)
                    }
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding({ left: 16, right: 16, top: 10 })
              }
            }

            // AniList 追踪（操作行"追踪"按钮控制显隐）
            if (this.showTrackingCard) {
              ListItem() {
              Column() {
                Text($r('app.string.detail_anilist_tracking'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal.text)
                  .width('100%')
                  .margin({ bottom: 8 })
                if (Settings.getAnilistToken() === '') {
                  Text($r('app.string.detail_anilist_token_hint'))
                    .fontSize(12)
                    .fontColor(this.pal.sub)
                } else if (this.track === undefined) {
                  if (this.alSearching) {
                    Row({ space: 8 }) {
                      LoadingProgress()
                        .width(16)
                        .height(16)
                        .color(this.pal.primary)
                      Text($r('app.string.detail_searching'))
                        .fontSize(12)
                        .fontColor(this.pal.sub)
                    }
                  } else {
                    Text($r('app.string.detail_search_and_bind'))
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .backgroundColor(this.pal.primary)
                      .borderRadius(14)
                      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                      .onClick(() => {
                        this.showAlSearch();
                      })
                  }
                  ForEach(this.alResults, (item: ALMediaItem) => {
                    Row() {
                      Text(item.title)
                        .fontSize(13)
                        .fontColor(this.pal.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      Text($r('app.string.detail_bind'))
                        .fontSize(12)
                        .fontColor(this.pal.primary)
                        .padding({ left: 8 })
                      .onClick(() => {
                        this.runSafe((): Promise<void> => this.bindAl(item));
                      })
                    }
                    .width('100%')
                    .padding({ top: 8, bottom: 8 })
                  }, (item: ALMediaItem) => `al-${item.id}`)
                } else {
                  Text(this.track.title)
                    .fontSize(13)
                    .fontColor(this.pal.text)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text($r('app.string.detail_synced_to_chapter', this.track.lastChapterRead))
                    .fontSize(11)
                    .fontColor(this.pal.sub)
                    .margin({ top: 2 })
                  Row({ space: 12 }) {
                    Text($r('app.string.detail_sync_progress'))
                      .fontSize(12)
                      .fontColor(this.pal.primary)
                      .backgroundColor(this.pal.chip)
                      .borderRadius(12)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .margin({ top: 8 })
                      .onClick(() => {
                        this.runSafe((): Promise<void> => this.syncTrack());
                      })
                    Text($r('app.string.detail_unbind'))
                      .fontSize(12)
                      .fontColor('#E05252')
                      .backgroundColor(this.pal.chip)
                      .borderRadius(12)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .margin({ top: 8 })
                      .onClick(() => {
                        this.runSafe((): Promise<void> => this.unbindAl());
                      })
                  }
                }
              }
               .width('100%')
               .alignItems(HorizontalAlign.Start)
               .padding(16)
               .backgroundColor(this.pal.card)
               .borderRadius(14)
               .margin({ left: 16, right: 16, top: 12 })
              }
            }

            // 章节标题栏：标题/排序/筛选入口 + 批量下载 + 全部已读（对齐 Mihon ChapterHeader）
            ListItem() {
              Row() {
                Text($r('app.string.detail_chapters_count', this.chapters.length))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal.text)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.showSettingsSheet = true;
                  })
                if (!ContentType.isLocal(this.manga.sourceKey)) {
                  AppIcon({ name: 'download', iconSize: 22, tint: this.pal.text })
                    .padding({ left: 10 })
                    .onClick(() => {
                      this.downloadAction(-1);
                    })
                    .bindMenu(this.bulkDownloadMenu)
                }
                AppIcon({
                  name: this.filterActive() ? 'filter_list' : 'sort',
                  iconSize: 22,
                  tint: this.filterActive() ? this.pal.primary : this.pal.text
                })
                  .padding({ left: 10 })
                  .onClick(() => {
                    this.showSettingsSheet = true;
                  })
                  .bindSheet($$this.showSettingsSheet, this.chapterSettingsSheetBuilder(), {
                    preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
                    width: Bp.isWide(this.windowW) ? 560 : '100%',
                    height: Bp.isWide(this.windowW) ? 560 : SheetSize.FIT_CONTENT,
                    detents: ['45%', SheetSize.LARGE],
                    showClose: false,
                    dragBar: true,
                    backgroundColor: this.pal.bg
                  })
                Text($r('app.string.detail_mark_all_read'))
                  .fontSize(13)
                  .fontColor(this.pal.primary)
                  .padding({ left: 10, right: 6, top: 6, bottom: 6 })
                   .onClick(() => {
                     this.runSafe((): Promise<void> => this.markAllRead());
                   })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 6 })
            }

            // 章节列表（分组承载分割线，随整页滚动）
            if (this.loading) {
              ListItem() {
                Column() {
                  LoadingProgress()
                    .width(36)
                    .height(36)
                    .color(this.pal.primary)
                }
                .width('100%')
                .padding({ top: 48, bottom: 48 })
                .justifyContent(FlexAlign.Center)
              }
            } else if (this.chapters.length === 0) {
              ListItem() {
                Column() {
                  EmptyScreen({ message: $r('app.string.detail_no_chapters') })
                }
                .width('100%')
                .padding({ top: 32, bottom: 32 })
              }
            } else {
              ListItemGroup() {
                LazyForEach(this.chapterSource, (chapter: ChapterRecord) => {
                  ListItem() {
                    DetailChapterRow({
                      chapter: chapter,
                      isLocalSource: ContentType.isLocal(this.manga.sourceKey),
                      selectionMode: this.selectedIds.size > 0,
                      selected: this.selectedIds.has(chapter.id),
                      onTap: (c: ChapterRecord): void => {
                        if (this.selectedIds.size > 0) {
                          this.toggleSelected(c.id);
                        } else {
                          this.openReader(c.id);
                        }
                      },
                      onLongPress: (c: ChapterRecord): void => {
                        this.toggleSelected(c.id);
                      },
                      onIndicatorTap: (c: ChapterRecord, state: string): void => {
                        this.onChapterIndicatorTap(c, state);
                      },
                    })
                  }
                }, (chapter: ChapterRecord) => `ch-${chapter.id}`)
              }
              .divider({
                strokeWidth: 1,
                color: this.pal.divider,
                startMargin: 16,
                endMargin: 16,
              })
            }
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Auto)
          .onScroll((_scrollOffset: number, _state: ScrollState) => {
            this.syncTopBar();
          })
          .onReachStart(() => {
            this.syncTopBar();
          })
        }
        .width('100%')
        .height('100%')
         .onRefreshing(() => {
           this.runSafe((): Promise<void> => this.refreshFromSource());
         })
        }
        .width('100%')
        .height('100%')

        // 吸顶栏：背景/标题随滚动渐显，返回按钮常驻
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(this.statusBarH + 52)
            .backgroundColor(this.pal.bg)
            .opacity(this.topBarProgress)
          Row() {
            Stack() {
              AppIcon({ name: 'arrow_back', iconSize: 22, tint: '#FFFFFF' })
                .opacity(1 - this.topBarProgress)
              AppIcon({ name: 'arrow_back', iconSize: 22, tint: this.pal.text })
                .opacity(this.topBarProgress)
            }
            .width(40)
            .height(40)
            .onClick(() => {
              this.pathStack.pop();
            })

            Text(this.manga.title)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 4 })
              .opacity(this.topBarProgress)

            if (this.syncing) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(this.topBarProgress > 0.5 ? this.pal.text : '#FFFFFF')
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .height(this.statusBarH + 52)
          .padding({ left: 8, right: 16, top: this.statusBarH })
          .alignItems(VerticalAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent)

        // 多选模式：底部动作条（对齐 Mihon 选择模式）
        if (this.selectedIds.size > 0) {
          Stack({ alignContent: Alignment.Bottom }) {
            this.selectionActionBar()
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as DetailParams;
      const mangaId = params !== undefined && params !== null ? params.mangaId : -1;
      if (!(mangaId > 0)) {
        // 参数缺失/非法：提示后退出页面，避免以 -1 继续加载产生脏数据
        Util.toastRes(this.getUIContext(), $r('app.string.detail_invalid_params'));
        this.pathStack.pop();
        return;
      }
      this.mangaId = mangaId;
      this.loadAll();
    })
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function MangaDetailBuilder() {
  MangaDetailPage()
}
