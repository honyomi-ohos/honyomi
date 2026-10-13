import { common, Want } from '@kit.AbilityKit';
import { formProvider, formInfo } from '@kit.FormKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, TrackRepo } from '../data/Repos';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord, TrackRecord, DownloadTask, ALMediaItem, ContentType } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ContentOpen } from './ContentOpen';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { CoverStore } from '../common/CoverStore';
import { DownloadService } from '../data/DownloadService';
import { WidgetUpdater } from '../form/WidgetUpdater';
import { AniListTracker } from '../data/AniListTracker';
import { InputDialog } from './components/Dialogs';
import { SmartImage } from './components/SmartImage';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';
import { PickerSheet } from './components/PickerSheet';

// 章节行：自订阅 DownloadService 变化刷新下载角标，
// 避免 ForEach key 携带全局版本号导致整个章节列表重建
@Component
struct DetailChapterRow {
  @Prop chapter: ChapterRecord = new ChapterRecord();
  @Prop isLocalSource: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State downloaded: boolean = false;
  @State queued: boolean = false;
  onTap: (chapter: ChapterRecord) => void = (_c: ChapterRecord) => {
  };
  onDownload: (chapter: ChapterRecord) => void = (_c: ChapterRecord) => {
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
    if (d !== this.downloaded || q !== this.queued) {
      this.downloaded = d;
      this.queued = q;
    }
  }

  build() {
    Row() {
      Column() {
        Text(this.chapter.name)
          .fontSize(14)
          .fontColor(this.chapter.read ? this.pal.sub : this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(Util.formatDate(this.chapter.dateUpload))
          .fontSize(11)
          .fontColor(this.pal.sub)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.chapter.read) {
        Text($r('app.string.detail_read'))
          .fontSize(11)
          .fontColor(this.pal.sub)
      } else {
        Text('NEW')
          .fontSize(10)
          .fontColor('#FFFFFF')
          .backgroundColor('#E05252')
          .borderRadius(8)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }

      if (!this.isLocalSource) {
        if (this.downloaded) {
          Text($r('app.string.detail_downloaded'))
            .fontSize(11)
            .fontColor(this.pal.primary)
            .margin({ left: 8 })
        } else if (this.queued) {
          Text($r('app.string.detail_in_queue'))
            .fontSize(11)
            .fontColor(this.pal.sub)
            .margin({ left: 8 })
        } else {
          Text($r('app.string.detail_download'))
            .fontSize(11)
            .fontColor(this.pal.sub)
            .margin({ left: 8 })
            .padding(4)
            .onClick(() => {
              this.onDownload(this.chapter);
            })
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(() => {
      this.onTap(this.chapter);
    })
  }
}

// 漫画详情页：整页滚动（头部随上滑收起）+ 下拉刷新全量更新章节 + 收藏 + 下载 + AniList 追踪
@Component
export struct MangaDetailPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapters: ChapterRecord[] = [];
  @State loading: boolean = true;
  @State sortAsc: boolean = false;
  @State descExpanded: boolean = false;
  @State syncing: boolean = false;
  @State refreshing: boolean = false;
  @State topBarProgress: number = 0;
  @State track: TrackRecord | undefined = undefined;
  @State alResults: ALMediaItem[] = [];
  @State alSearching: boolean = false;
  @State showCoverSheet: boolean = false;
  private mangaId: number = -1;
  private listScroller: Scroller = new Scroller();

  onLibDirty(): void {
    this.reloadLocal();
  }

  private async loadAll(): Promise<void> {
    await this.reloadLocal();
    await this.syncFromSource();
    this.track = await TrackRepo.get(this.mangaId);
  }

  private async reloadLocal(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await AppDb.ready(context);
    const record = await MangaRepo.get(this.mangaId);
    if (record !== undefined) {
      this.manga = record;
    }
    this.chapters = await ChapterRepo.listByManga(this.mangaId);
    this.loading = false;
  }

  private async syncFromSource(): Promise<void> {
    if (this.syncing) {
      return;
    }
    this.syncing = true;
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
    }
    await this.reloadLocal();
    this.syncing = false;
  }

  // 下拉刷新：全量重新同步源数据（含源端已删除章节的移除）
  private async refreshFromSource(): Promise<void> {
    try {
      await this.syncFromSource();
    } finally {
      this.refreshing = false;
    }
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

  private shownChapters(): ChapterRecord[] {
    if (this.sortAsc) {
      return this.chapters;
    }
    return this.chapters.slice().reverse();
  }

  private async toggleLibrary(): Promise<void> {
    const target = !this.manga.inLibrary;
    await MangaRepo.setInLibrary(this.manga.id, target);
    await this.reloadLocal();
    AppStorage.set('libDirty', this.libDirty + 1);
    Util.toastRes(this.getUIContext(), target ? $r('app.string.detail_added_to_library') : $r('app.string.detail_removed_from_library'));
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
      const context = getContext(this) as common.UIAbilityContext;
      const coverPath = await CoverStore.save(context, this.mangaId, uris[0]);
      if (coverPath === '') {
        Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_save_failed'));
        return;
      }
      await MangaRepo.applyCustomCover(this.mangaId, coverPath);
      await this.reloadLocal();
      AppStorage.set('libDirty', this.libDirty + 1);
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_updated'));
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_save_failed'));
    }
  }

  // 恢复原封面（对齐 Mihon Reset cover）：删除自定义封面文件，回退到源封面地址
  private async resetCover(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    CoverStore.remove(context, this.mangaId);
    await MangaRepo.resetCover(this.mangaId);
    await this.reloadLocal();
    AppStorage.set('libDirty', this.libDirty + 1);
    Util.toastRes(this.getUIContext(), $r('app.string.detail_cover_reset'));
  }

  private coverSheetOptions(): ResourceStr[] {
    const options: ResourceStr[] = [$r('app.string.detail_edit_cover')];
    if (this.manga.origThumbnail !== '') {
      options.push($r('app.string.detail_reset_cover'));
    }
    return options;
  }

  private coverSheetIcons(): string[] {
    return this.manga.origThumbnail !== '' ? ['edit', 'refresh'] : ['edit'];
  }

  @Builder
  coverSheetBuilder() {
    PickerSheet({
      options: this.coverSheetOptions(),
      icons: this.coverSheetIcons(),
      onPick: (index: number): void => {
        this.showCoverSheet = false;
        if (index === 0) {
          this.editCover();
        } else if (index === 1) {
          this.resetCover();
        }
      }
    })
  }

  private continueChapter(): ChapterRecord | undefined {
    if (this.chapters.length === 0) {
      return undefined;
    }
    for (const chapter of this.chapters) {
      if (!chapter.read) {
        return chapter;
      }
    }
    return this.chapters[this.chapters.length - 1];
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
    const context = getContext(this) as common.UIAbilityContext;
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
    await this.reloadLocal();
    AppStorage.set('libDirty', this.libDirty + 1);
    Util.toastRes(this.getUIContext(), $r('app.string.detail_all_marked_read'));
  }

  private async downloadChapter(chapter: ChapterRecord): Promise<void> {
    if (ContentType.isLocal(this.manga.sourceKey)) {
      return;
    }
    if (this.manga.contentType === ContentType.VIDEO) {
      const source = SourceRegistry.get(this.manga.sourceKey);
      if (source === undefined) {
        Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'), ['源不可用']);
        return;
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
          Util.toastRes(this.getUIContext(), $r('app.string.detail_download_stream_only'));
          return;
        }
      } catch (e) {
        Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'), [(e as Error).message]);
        return;
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
    Util.toastRes(this.getUIContext(), $r('app.string.detail_download_queued'));
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
          this.doAlSearch(text);
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

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
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
                  Column()
                    .width('100%')
                    .height(this.headerHeight())
                    .backgroundColor(this.pal.chip)
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
                    // 封面（长按更换/恢复，对齐 Mihon）
                    Stack() {
                      if (this.manga.thumbnailUrl !== '') {
                        SmartImage({ url: this.manga.thumbnailUrl, sourceKey: this.manga.sourceKey, fit: ImageFit.Cover, fill: true })
                      } else {
                        Column() {
                          AppIcon({ name: 'photo', iconSize: 30 })
                        }
                        .width('100%')
                        .height('100%')
                        .justifyContent(FlexAlign.Center)
                      }
                    }
                    .width(110)
                    .height(150)
                    .borderRadius(10)
                    .clip(true)
                    .backgroundColor(this.pal.chip)
                    .gesture(
                      LongPressGesture()
                        .onAction(() => {
                          this.showCoverSheet = true;
                        })
                    )
                    .bindSheet($$this.showCoverSheet, this.coverSheetBuilder(), {
                      preferType: SheetType.BOTTOM,
                      title: { title: $r('app.string.detail_cover_actions') },
                      detents: [SheetSize.FIT_CONTENT],
                      dragBar: true,
                      showClose: false,
                      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
                    })
                    Column({ space: 6 }) {
                      Text(this.manga.title)
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.pal.text)
                        .maxLines(3)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (this.manga.author !== '') {
                        Text(this.manga.author)
                          .fontSize(13)
                          .fontColor(this.pal.sub)
                          .maxLines(1)
                      }
                      Text(ContentType.isLocal(this.manga.sourceKey) ? $r('app.string.detail_status_local') : Util.statusLabel(this.manga.status))
                        .fontSize(12)
                        .fontColor(this.pal.primary)
                        .backgroundColor(this.pal.chip)
                        .borderRadius(8)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
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

            // 操作按钮
            ListItem() {
              Row({ space: 12 }) {
                Button(this.manga.inLibrary ? $r('app.string.detail_in_library') : $r('app.string.detail_add_to_library'))
                  .fontSize(14)
                  .height(38)
                  .layoutWeight(1)
                  .backgroundColor(this.manga.inLibrary ? this.pal.chip : this.pal.primary)
                  .fontColor(this.manga.inLibrary ? this.pal.text : '#FFFFFF')
                  .onClick(() => {
                    this.toggleLibrary();
                  })
                Button(this.actionLabel())
                  .fontSize(14)
                  .height(38)
                  .layoutWeight(1)
                  .backgroundColor(this.pal.chip)
                  .fontColor(this.pal.text)
                  .onClick(() => {
                    const chapter = this.continueChapter();
                    if (chapter !== undefined) {
                      this.openReader(chapter.id);
                    }
                  })
                if (this.manga.inLibrary) {
                  Button($r('app.string.detail_add_to_desktop'))
                    .fontSize(14)
                    .height(38)
                    .layoutWeight(1)
                    .backgroundColor(this.pal.chip)
                    .fontColor(this.pal.text)
                    .onClick(() => {
                      this.addToDesktop();
                    })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12 })
            }

            // 简介
            if (this.manga.description !== '') {
              ListItem() {
                Column() {
                  Text(this.manga.description)
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
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding({ left: 16, right: 16, top: 10 })
              }
            }

            // AniList 追踪
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
                          this.bindAl(item);
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
                        this.syncTrack();
                      })
                    Text($r('app.string.detail_unbind'))
                      .fontSize(12)
                      .fontColor('#E05252')
                      .backgroundColor(this.pal.chip)
                      .borderRadius(12)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .margin({ top: 8 })
                      .onClick(() => {
                        this.unbindAl();
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

            // 章节标题栏
            ListItem() {
              Row() {
                Text($r('app.string.detail_chapters_count', this.chapters.length))
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal.text)
                  .layoutWeight(1)
                Text(this.sortAsc ? $r('app.string.detail_sort_asc') : $r('app.string.detail_sort_desc'))
                  .fontSize(13)
                  .fontColor(this.pal.primary)
                  .padding(6)
                  .onClick(() => {
                    this.sortAsc = !this.sortAsc;
                  })
                Text($r('app.string.detail_mark_all_read'))
                  .fontSize(13)
                  .fontColor(this.pal.primary)
                  .padding(6)
                  .onClick(() => {
                    this.markAllRead();
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
                ForEach(this.shownChapters(), (chapter: ChapterRecord) => {
                  ListItem() {
                    DetailChapterRow({
                      chapter: chapter,
                      isLocalSource: ContentType.isLocal(this.manga.sourceKey),
                      onTap: (c: ChapterRecord): void => {
                        this.openReader(c.id);
                      },
                      onDownload: (c: ChapterRecord): void => {
                        this.downloadChapter(c);
                      },
                    })
                  }
                }, (chapter: ChapterRecord) => `ch-${chapter.id}-${chapter.read}`)
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
          this.refreshFromSource();
        })

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
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as DetailParams;
      this.mangaId = params !== undefined && params !== null ? params.mangaId : -1;
      this.loadAll();
    })
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function MangaDetailBuilder() {
  MangaDetailPage()
}
