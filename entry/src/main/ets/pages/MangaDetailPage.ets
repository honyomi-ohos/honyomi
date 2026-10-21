import { Want } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { formInfo, formProvider } from '@kit.FormKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppDb } from '../data/AppDb';
import { CategoryRepo, ChapterRepo, MangaRepo, TrackRepo } from '../data/Repos';
import { SourceRegistry } from '../source/Source';
import { CategoryRecord, ChapterRecord, ContentType, DownloadTask, MangaRecord, SManga } from '../model/Models';
import { DetailParams, DetailSearchResult, GlobalSearchParams } from '../model/RouteParams';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { CoverStore } from '../common/CoverStore';
import { ChapterFlags } from '../common/ChapterFlags';
import { NaturalCompare } from '../common/NaturalCompare';
import { DownloadService } from '../data/DownloadService';
import { DownloadRules } from '../data/DownloadRules';
import { BtFlow } from '../data/BtFlow';
import { Settings } from '../common/Settings';
import { WidgetUpdater } from '../form/WidgetUpdater';
import { CategoryDialog, ConfirmDialog } from './components/Dialogs';
import { SmartImage } from './components/SmartImage';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';
import { CoverViewer } from './components/CoverViewer';
import { CoverPlaceholder } from './components/CoverPlaceholder';
import { ChapterSettingsSheet } from './components/ChapterSettingsSheet';
import { TrackSheet } from './components/TrackSheet';

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

  // PC 鼠标右键菜单「选择」：进入多选（与长按一致；移动端仍走长按手势）
  @Builder
  chapterContextMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.common_select') })
        .onClick(() => {
          this.onLongPress(this.chapter);
        })
    }
  }
  // 指示器点击：state 为行内当前下载状态（none/downloading/queued/downloaded）
  onIndicatorTap: (chapter: ChapterRecord, state: string) => void = (_c: ChapterRecord, _s: string) => {
  };

  aboutToAppear(): void {
    this.refreshDlState();
    DownloadService.addListener(this.onDlNotify);
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onDlNotify);
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
            Column()
              .width(6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(this.pal.primary)
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
    .padding({
      left: 16,
      right: 12,
      top: 10,
      bottom: 10
    })
    .onClick((event?: ClickEvent) => {
      if (event !== undefined && Util.isCtrlHeld(event)) {
        this.onLongPress(this.chapter);
      } else {
        this.onTap(this.chapter);
      }
    })
    .gesture(LongPressGesture({ repeat: false })
      .onAction(() => {
        this.onLongPress(this.chapter);
      }))
    .bindContextMenu(this.chapterContextMenu, ResponseType.RightClick)
  }

  private onDlNotify = (): void => {
    this.refreshDlState();
  };

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
  @State trackCount: number = 0;
  @State showTrackSheet: boolean = false;
  // 相关/推荐作品（插件可选导出 getRelatedWorks；为空不渲染该区块）
  @State relatedWorks: SManga[] = [];
  @State showCoverViewer: boolean = false;
  @State showSettingsSheet: boolean = false;
  // Index 根节点 Esc 广播：关闭追踪/章节设置弹层（计数器递增触发）
  @StorageLink('sheetEsc') @Watch('onSheetEsc') sheetEsc: number = 0;
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

  aboutToAppear(): void {
    DownloadService.addListener(this.onDlNotify);
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onDlNotify);
  }

  // ----- 头部信息（对齐 Mihon MangaContentInfo） -----

  onLibDirty(): void {
    this.runSafe((): Promise<void> => this.reloadLocal());
  }

  // 标签 chip（对齐 Mihon TagsChip）：点击弹出 搜索/复制 菜单
  @Builder
  TagChip(tag: string) {
    Text(tag)
      .fontSize(12)
      .fontColor(this.pal.text)
      .backgroundColor(this.pal.chip)
      .borderRadius(14)
      .padding({
        left: 12,
        right: 12,
        top: 5,
        bottom: 5
      })
      .margin({ right: 6, top: 6 })
      .bindMenu((): void => {
        this.TagMenu(tag);
      })
  }

  // 搜索 = 回上一页按标签过滤/搜索；复制到剪贴板 = 复制标签文本
  @Builder
  TagMenu(tag: string) {
    Menu() {
      MenuItem({ content: $r('app.string.common_search') })
        .onClick(() => {
          this.searchGenreInPrevious(tag);
        })
      MenuItem({ content: $r('app.string.common_copy_to_clipboard') })
        .onClick(() => {
          this.copyText(tag);
        })
    }
  }

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

  // 非全局搜索（对齐 Mihon performSearch global=false）：目标为路由栈中详情页的下一页——
  // 单源浏览页 → 回退后页内文本搜索；详情页直接压在主页上 → 切书架页签文本搜索；

  // 追踪弹层（对齐 Mihon TrackSheet）
  @Builder
  trackSheetBuilder() {
    TrackSheet({
      mangaId: this.mangaId,
      mangaTitle: this.manga.title,
      hasReadChapters: this.hasReadChapters(),
      onChanged: (): void => {
        this.runSafe((): Promise<void> => this.refreshTrackCount());
      },
      onClose: (): void => {
        this.showTrackSheet = false;
      },
    })
  }

  // 标签搜索（对齐 Mihon performGenreSearch）：上一页为单源浏览页时回退后按标签过滤/搜索

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

  // 章节行下载指示器点击（对齐 Mihon ChapterDownloadIndicator 交互）：

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
      .padding({
        top: 6,
        bottom: 14,
        left: 20,
        right: 20
      })
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .constraintSize({ maxWidth: 720 })
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
                    SmartImage({
                      url: this.manga.thumbnailUrl,
                      sourceKey: this.manga.sourceKey,
                      fit: ImageFit.Cover,
                      fill: true
                    })
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
                          SmartImage({
                            url: this.manga.thumbnailUrl,
                            sourceKey: this.manga.sourceKey,
                            fit: ImageFit.Cover,
                            fill: true
                          })
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
                      // 标题、作者点击跳全局搜索，长按复制；源名点击回上一页文本搜索
                      // PC 右键标题/作者复制（移动端仍走长按复制）
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
                          .gesture(LongPressGesture({ repeat: false })
                            .onAction(() => {
                              this.copyText(this.manga.title);
                            }))
                          .bindContextMenu(this.titleContextMenu, ResponseType.RightClick)
                        if (this.manga.author !== '') {
                          Text(this.manga.author)
                            .fontSize(13)
                            .fontColor(this.pal.sub)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .onClick(() => {
                              this.searchGlobal(this.manga.author);
                            })
                            .gesture(LongPressGesture({ repeat: false })
                              .onAction(() => {
                                this.copyText(this.manga.author);
                              }))
                            .bindContextMenu(this.authorContextMenu, ResponseType.RightClick)
                        }
                        Row({ space: 4 }) {
                          AppIcon({
                            name: this.statusIconName(),
                            iconSize: 15,
                            tint: this.pal.primary
                          })
                          Text(ContentType.isLocal(this.manga.sourceKey) ? $r('app.string.detail_status_local') :
                            Util.statusLabel(this.manga.status))
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
                            .onClick(() => {
                              // 源名点击：回上一页（单源浏览页/书架）按源名文本搜索
                              this.searchInPrevious(this.sourceDisplayName());
                            })
                        }
                        .width('100%')
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                    }
                    .width('100%')
                    .padding({
                      left: 16 + this.contentInset(),
                      right: 16 + this.contentInset(),
                      top: 12
                    })
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
                    Text(this.manga.inLibrary ? $r('app.string.detail_in_library') :
                      $r('app.string.detail_add_to_library'))
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
                      tint: this.trackCount > 0 ? this.pal.primary : this.pal.sub
                    })
                    Text($r('app.string.detail_action_tracking'))
                      .fontSize(11)
                      .maxLines(2)
                      .textAlign(TextAlign.Center)
                      .fontColor(this.trackCount > 0 ? this.pal.primary : this.pal.sub)
                  }
                  .layoutWeight(1)
                  .onClick(() => {
                    this.showTrackSheet = true;
                  })
                  .bindSheet($$this.showTrackSheet, this.trackSheetBuilder(), {
                    preferType: Bp.sheetType(this.windowW),
                    width: Bp.sheetWidth(this.windowW),
                    height: Bp.sheetHeight(this.windowW),
                    detents: ['75%', SheetSize.LARGE],
                    dragBar: true,
                    showClose: false,
                    backgroundColor: this.pal.bg
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
                .padding({
                  left: 8 + this.contentInset(),
                  right: 8 + this.contentInset(),
                  top: 14
                })
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
                   .padding({
                     left: 16 + this.contentInset(),
                     right: 16 + this.contentInset(),
                     top: 10
                   })
                }
              }

              // 相关/推荐作品（插件导出 getRelatedWorks 时展示）：横向封面卡片，点击入库并进详情
              if (this.relatedWorks.length > 0) {
                ListItem() {
                  Column() {
                    Text($r('app.string.detail_related_works'))
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.pal.text)
                    Scroll() {
                      Row({ space: 10 }) {
                        ForEach(this.relatedWorks, (m: SManga) => {
                          Column() {
                            SmartImage({
                              url: m.coverUrl,
                              sourceKey: this.manga.sourceKey,
                              fit: ImageFit.Cover,
                              fill: true
                            })
                              .width('100%')
                              .aspectRatio(0.7)
                              .borderRadius(8)
                              .clip(true)
                              .backgroundColor(this.pal.chip)
                            Text(m.title)
                              .fontSize(11)
                              .fontColor(this.pal.sub)
                              .maxLines(2)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .margin({ top: 5 })
                          }
                          .width(88)
                          .alignItems(HorizontalAlign.Start)
                          .onClick(() => {
                            this.runSafe((): Promise<void> => this.openRelatedWork(m));
                          })
                        }, (m: SManga, idx: number) => `rel-${idx}-${m.key}`)
                      }
                    }
                    .scrollable(ScrollDirection.Horizontal)
                    .scrollBar(BarState.Off)
                    .edgeEffect(EdgeEffect.None)
                    .margin({ top: 10 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .padding({
                    left: 16 + this.contentInset(),
                    right: 16 + this.contentInset(),
                    top: 10
                  })
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
                      preferType: Bp.sheetType(this.windowW),
                      width: Bp.sheetWidth(this.windowW),
                      height: Bp.sheetHeight(this.windowW),
                      detents: ['45%', SheetSize.LARGE],
                      showClose: false,
                      dragBar: true,
                      backgroundColor: this.pal.bg
                    })
                  Text($r('app.string.detail_mark_all_read'))
                    .fontSize(13)
                    .fontColor(this.pal.primary)
                    .padding({
                      left: 10,
                      right: 6,
                      top: 6,
                      bottom: 6
                    })
                    .onClick(() => {
                      this.runSafe((): Promise<void> => this.markAllRead());
                    })
                }
                .width('100%')
                .padding({
                  left: 16 + this.contentInset(),
                  right: 16 + this.contentInset(),
                  top: 14,
                  bottom: 6
                })
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
                    .padding({
                      left: this.contentInset(),
                      right: this.contentInset()
                    })
                  }, (chapter: ChapterRecord) => `ch-${chapter.id}`)
                }
                .divider({
                  strokeWidth: 1,
                  color: this.pal.divider,
                  startMargin: 16 + this.contentInset(),
                  endMargin: 16 + this.contentInset(),
                })
              }
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Auto)
            .onDidScroll((_scrollOffset: number, _state: ScrollState) => {
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
          .padding({
            left: 8 + this.contentInset(),
            right: 16 + this.contentInset(),
            top: this.statusBarH
          })
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

  // 全局搜索跳转（标题/作者点击，对齐 Mihon doSearch(query, global=true)）
  private searchGlobal(query: string): void {
    const params: GlobalSearchParams = { query: query };
    this.pathStack.pushPathByName('GlobalSearch', params);
  }

  // 其余（全局搜索页等）不处理
  private searchInPrevious(query: string): void {
    const q = query.trim();
    if (q === '') {
      return;
    }
    const names: string[] = this.pathStack.getAllPathName();
    if (names.length >= 2 && names[names.length - 2] === 'BrowseSource') {
      const result: DetailSearchResult = { action: 'search', query: q };
      this.pathStack.pop(result);
      return;
    }
    if (names.length === 1) {
      // 详情页直接位于主页之上：切书架页签并以文本搜索（对齐 Mihon HomeScreen.search → LibraryTab）
      AppStorage.setOrCreate(AppKeys.LIB_SEARCH_QUERY, q);
      AppStorage.setOrCreate(AppKeys.LIB_SEARCH_REQ, (AppStorage.get<number>(AppKeys.LIB_SEARCH_REQ) ?? 0) + 1);
      this.pathStack.pop();
    }
  }

  // （源支持过滤器时置 INCLUDE，否则文本搜索回退）；其余场景走非全局搜索（书架文本搜索）
  private searchGenreInPrevious(genre: string): void {
    const names: string[] = this.pathStack.getAllPathName();
    if (names.length >= 2 && names[names.length - 2] === 'BrowseSource') {
      const result: DetailSearchResult = { action: 'searchGenre', query: genre.trim() };
      this.pathStack.pop(result);
      return;
    }
    this.searchInPrevious(genre);
  }

  // 复制文本到剪贴板（标签菜单“复制”、标题/作者长按，对齐 Mihon onCopyTagToClipboard）
  private copyText(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_tag_copied'));
    }).catch((_e: BusinessError) => {
      Util.toastRes(this.getUIContext(), $r('app.string.common_op_failed'));
    });
  }

  // PC 右键复制标题（移动端仍走长按复制）
  @Builder
  titleContextMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.common_copy_to_clipboard') })
        .onClick(() => {
          this.copyText(this.manga.title);
        })
    }
  }

  // PC 右键复制作者（移动端仍走长按复制）
  @Builder
  authorContextMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.common_copy_to_clipboard') })
        .onClick(() => {
          this.copyText(this.manga.author);
        })
    }
  }

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

  private async loadAll(): Promise<void> {
    try {
      await this.syncFromSource();
      await this.refreshTrackCount();
      await this.loadRelatedWorks();
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${e}`;
      hilog.warn(0x0001, 'MangaDetail', 'loadAll failed: %{public}s', msg);
      Util.toastRes(this.getUIContext(), $r('app.string.detail_load_failed'));
    } finally {
      this.loading = false;
    }
  }

  // 相关/推荐作品：插件导出 getRelatedWorks 时加载（失败静默，不阻塞详情主流程）。
  // 排除自身后最多展示 20 项。
  private async loadRelatedWorks(): Promise<void> {
    try {
      const source = SourceRegistry.get(this.manga.sourceKey);
      if (source === undefined) {
        this.relatedWorks = [];
        return;
      }
      const list = await source.getRelatedWorks(this.manga.url);
      const filtered: SManga[] = [];
      for (const m of list) {
        if (m.key !== this.manga.url && filtered.length < 20) {
          filtered.push(m);
        }
      }
      this.relatedWorks = filtered;
    } catch (e) {
      this.relatedWorks = [];
    }
  }

  // 点击相关作品：入库（upsertFromSource）后压入详情页
  private async openRelatedWork(m: SManga): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const source = SourceRegistry.get(this.manga.sourceKey);
      const contentType = source !== undefined ? source.contentType : '';
      const id = await MangaRepo.upsertFromSource(this.manga.sourceKey, m, contentType);
      const params: DetailParams = { mangaId: id };
      this.pathStack.pushPathByName('MangaDetail', params);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_open_detail_failed'));
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
          const detail = await source.getWorkDetail(this.manga.url);
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

  // 从持久化标志位解码排序/筛选状态（对齐 Mihon Manga.chapterFlags 解码）

  // 下拉刷新：全量重新同步源数据（含源端已删除章节的移除）
  private async refreshFromSource(): Promise<void> {
    try {
      await this.syncFromSource();
    } finally {
      this.refreshing = false;
    }
  }

  // 当前漫画的追踪记录数（操作行"追踪"按钮着色）
  private async refreshTrackCount(): Promise<void> {
    const list = await TrackRepo.listByManga(this.mangaId);
    this.trackCount = list.length;
  }

  // 是否存在已读章节（注册追踪时远端合并进度用）
  private hasReadChapters(): boolean {
    for (const c of this.chapters) {
      if (c.read) {
        return true;
      }
    }
    return false;
  }

  // 展示顺序：先按三态筛选过滤（对齐 Mihon applyFilters），再按排序模式/方向排序。
  // 本地源 sortOrder 已按自然顺序（含中文数字）生成，"按源顺序"即为真实章节顺序；

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

  // 大屏响应式限宽缩进：内容列限宽 720vp 居中，超出部分左右留白；
  // 虚化封面背景保持全宽，仅内容（信息/操作/简介/章节）随缩进收窄
  private contentInset(): number {
    return Bp.contentInset(this.windowW);
  }

  // 吸顶栏渐显进度：随滚动偏移 0 → 1
  // Esc 广播：关闭追踪/章节设置半模态弹层
  onSheetEsc(): void {
    if (this.showTrackSheet) {
      this.showTrackSheet = false;
    }
    if (this.showSettingsSheet) {
      this.showSettingsSheet = false;
    }
  }

  private syncTopBar(): void {
    const y = this.listScroller.currentOffset().yOffset;
    const p = Math.min(1, Math.max(0, y / 180));
    if (p !== this.topBarProgress) {
      this.topBarProgress = p;
    }
  }

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

  // 标签菜单（对齐 Mihon TagsChip DropdownMenu）：

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

  // 封面查看器（对齐 Mihon MangaCoverDialog）：点击封面进入全屏查看，

  private async toggleLibrary(): Promise<void> {
    if (this.manga.inLibrary) {
      // 移出书架：直接执行
      await MangaRepo.setInLibrary(this.manga.id, false);
      AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
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
    AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
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
      AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
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
      AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
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
    AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
    Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_reset'));
  }

  // 单章入队校验（视频源先检查是否有直链可下载）

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
    // BT 视频章节（magnet/.torrent 直链）不支持在线流播：分流到专用流程
    if (this.manga.contentType === ContentType.VIDEO) {
      const chapter = this.chapters.find((c: ChapterRecord): boolean => c.id === chapterId);
      if (chapter !== undefined && DownloadService.isBtUrl(chapter.url)) {
        this.runSafe((): Promise<void> => this.openBtChapter(chapter));
        return;
      }
    }
    ContentOpen.push(this.pathStack, this.manga.contentType, this.mangaId, chapterId);
  }

  // BT 章节点击：已完整下载→直接播本地；未下载→引擎选择（可记住）：
  // module=入队且边下边播开启时立即进播放器等待起播（关闭则仅入队提示）；
  // system=移交系统下载应用；cancel=无操作
  private async openBtChapter(chapter: ChapterRecord): Promise<void> {
    if (DownloadService.isDownloaded(chapter.id)) {
      ContentOpen.push(this.pathStack, this.manga.contentType, this.mangaId, chapter.id);
      return;
    }
    const choice = await BtFlow.acquireEngineChoice(this.getUIContext());
    if (choice === 'cancel') {
      return;
    }
    if (choice === 'system') {
      await BtFlow.handOffToSystem(this.getUIContext(), chapter.url);
      return;
    }
    // 用户明确选择内置引擎：解除安装引导抑制（此前"暂不"仅抑制自动弹窗）
    AppStorage.setOrCreate(AppKeys.BT_ASK_DISMISSED, false);
    const status = await this.enqueueDownload(chapter);
    if (status !== 'ok') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_failed'));
      return;
    }
    if (Settings.getBtProgressive()) {
      ContentOpen.push(this.pathStack, this.manga.contentType, this.mangaId, chapter.id);
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_queued'));
    }
  }

  // 批量入队（多选下载 / 下载菜单）：两个 worker 共享递增游标实现 2 并发，

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

  // 下载菜单动作（对齐 Mihon DownloadAction）：count>0 取展示顺序前 N 个未读，

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

  // ----- 多选操作（对齐 Mihon 章节多选底部动作菜单） -----

  private async markAllRead(): Promise<void> {
    await ChapterRepo.markAllRead(this.mangaId, true);
    // 手动全部标记已读：按下载设置删除已读章节的下载
    DownloadRules.onDeleteAllRead(this.mangaId);
    AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
    Util.toastRes(this.getUIContext(), $r('app.string.detail_all_marked_read'));
  }

  // 返回：'ok' 已入队 | 'failed' 校验/入队失败
  // 视频章节不做入队前流校验：直链与 m3u8 均可下载（m3u8 走 HLS 管线），流类型由下载时判定
  private async enqueueDownload(chapter: ChapterRecord): Promise<string> {
    if (ContentType.isLocal(this.manga.sourceKey)) {
      return 'failed';
    }
    if (SourceRegistry.get(this.manga.sourceKey) === undefined) {
      return 'failed';
    }
    const task = new DownloadTask();
    task.mangaId = this.mangaId;
    task.mangaTitle = this.manga.title;
    task.chapterId = chapter.id;
    task.chapterName = chapter.name;
    task.chapterNumber = chapter.chapterNumber;
    task.dateUpload = chapter.dateUpload;
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
    // BT 章节单下载：同样走引擎选择，但不进播放器
    if (DownloadService.isBtUrl(chapter.url)) {
      await this.downloadBtChapter(chapter);
      return;
    }
    const status = await this.enqueueDownload(chapter);
    if (status === 'ok') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_queued'));
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_failed'));
    }
  }

  // BT 章节下载（指示器点击/单章下载入口）：module 入队、system 移交、cancel 无操作
  private async downloadBtChapter(chapter: ChapterRecord): Promise<void> {
    const choice = await BtFlow.acquireEngineChoice(this.getUIContext());
    if (choice === 'cancel') {
      return;
    }
    if (choice === 'system') {
      await BtFlow.handOffToSystem(this.getUIContext(), chapter.url);
      return;
    }
    AppStorage.setOrCreate(AppKeys.BT_ASK_DISMISSED, false);
    const status = await this.enqueueDownload(chapter);
    if (status === 'ok') {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_queued'));
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_failed'));
    }
  }

  // 完成后统一提示入队数量（BT 章节按引擎选择分流，不进 2 并发 worker）
  private async downloadChapters(list: ChapterRecord[]): Promise<void> {
    if (ContentType.isLocal(this.manga.sourceKey) || list.length === 0) {
      return;
    }
    const btList: ChapterRecord[] = [];
    const normalList: ChapterRecord[] = [];
    for (const c of list) {
      if (DownloadService.isBtUrl(c.url)) {
        btList.push(c);
      } else {
        normalList.push(c);
      }
    }
    let count = 0;
    if (btList.length > 0) {
      const choice = await BtFlow.acquireEngineChoice(this.getUIContext());
      if (choice === 'system') {
        // 系统应用逐个弹选择器不可行：仅移交第一个，其余跳过提示
        await BtFlow.handOffToSystem(this.getUIContext(), btList[0].url);
        if (btList.length > 1) {
          Util.toastRes(this.getUIContext(), $r('app.string.bt_batch_skipped'), [btList.length - 1]);
        }
      } else if (choice === 'module') {
        AppStorage.setOrCreate(AppKeys.BT_ASK_DISMISSED, false);
        for (const chapter of btList) {
          const status = await this.enqueueDownload(chapter);
          if (status === 'ok') {
            count += 1;
          }
        }
      }
    }
    let index = 0;
    const worker = async (): Promise<void> => {
      while (index < normalList.length) {
        const chapter = normalList[index];
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
    } else if (btList.length === 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_download_failed'));
    }
  }

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
    // 手动标记已读：按下载设置删除对应下载
    if (read) {
      DownloadRules.onDeleteMarkedRead(this.mangaId, ids);
    }
    AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
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
    AppStorage.set(AppKeys.LIB_DIRTY, this.libDirty + 1);
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
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function MangaDetailBuilder() {
  MangaDetailPage()
}
