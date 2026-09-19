import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, TrackRepo } from '../data/Repos';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord, TrackRecord, DownloadTask, ALMediaItem } from '../model/Models';
import { DetailParams, ReaderParams } from '../model/RouteParams';
import { Theme } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { DownloadService } from '../data/DownloadService';
import { AniListTracker } from '../data/AniListTracker';
import { InputDialog } from './components/Dialogs';
import { SmartImage } from './components/SmartImage';

// 漫画详情页：信息 + 章节列表 + 收藏 + 下载 + AniList 追踪
@Component
export struct MangaDetailPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageLink('libDirty') @Watch('onLibDirty') libDirty: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapters: ChapterRecord[] = [];
  @State loading: boolean = true;
  @State sortAsc: boolean = false;
  @State descExpanded: boolean = false;
  @State syncing: boolean = false;
  @State track: TrackRecord | undefined = undefined;
  @State alResults: ALMediaItem[] = [];
  @State alSearching: boolean = false;
  @State dlVersion: number = 0;
  private mangaId: number = -1;

  private onDownloadChanged = (): void => {
    this.dlVersion += 1;
  }

  aboutToAppear(): void {
    DownloadService.addListener(this.onDownloadChanged);
  }

  aboutToDisappear(): void {
    DownloadService.removeListener(this.onDownloadChanged);
  }

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
        await MangaRepo.upsertFromSource(this.manga.sourceKey, detail);
      } catch (e) {
        Util.toast(this.getUIContext(), '联网同步失败，展示本地缓存');
      }
    }
    await this.reloadLocal();
    this.syncing = false;
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
    Util.toast(this.getUIContext(), target ? '已加入书架' : '已移出书架');
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
    const params: ReaderParams = { mangaId: this.mangaId, chapterId: chapterId };
    this.pathStack.pushPathByName('Reader', params);
  }

  private async markAllRead(): Promise<void> {
    await ChapterRepo.markAllRead(this.mangaId, true);
    await this.reloadLocal();
    AppStorage.set('libDirty', this.libDirty + 1);
    Util.toast(this.getUIContext(), '已全部标为已读');
  }

  private downloadChapter(chapter: ChapterRecord): void {
    if (this.manga.sourceKey === 'local') {
      return;
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
    this.dlVersion += 1;
    Util.toast(this.getUIContext(), '已加入下载队列');
  }

  private showAlSearch(): void {
    if (Settings.getAnilistToken() === '') {
      Util.toast(this.getUIContext(), '请先在「更多」页配置 AniList 令牌');
      return;
    }
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: '搜索 AniList',
        placeholder: '漫画名称',
        onConfirm: (text: string): void => {
          this.doAlSearch(text);
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
      this.alResults = await AniListTracker.search(q, token);
      if (this.alResults.length === 0) {
        Util.toast(this.getUIContext(), '无搜索结果');
      }
    } catch (e) {
      Util.toast(this.getUIContext(), 'AniList 搜索失败');
    }
    this.alSearching = false;
  }

  private async bindAl(item: ALMediaItem): Promise<void> {
    await TrackRepo.bind(this.mangaId, item.id, item.title);
    this.track = await TrackRepo.get(this.mangaId);
    this.alResults = [];
    Util.toast(this.getUIContext(), '已绑定 AniList 条目');
  }

  private async unbindAl(): Promise<void> {
    await TrackRepo.unbind(this.mangaId);
    this.track = undefined;
    this.alResults = [];
    Util.toast(this.getUIContext(), '已解绑');
  }

  private async syncTrack(): Promise<void> {
    if (this.track === undefined) {
      return;
    }
    const token = Settings.getAnilistToken();
    if (token === '') {
      Util.toast(this.getUIContext(), '请先在「更多」页配置 AniList 令牌');
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
      Util.toast(this.getUIContext(), `已同步进度到第 ${progress} 话`);
    } catch (e) {
      Util.toast(this.getUIContext(), 'AniList 同步失败');
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 头部：封面背景 + 信息
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.manga.thumbnailUrl !== '') {
            SmartImage({ url: this.manga.thumbnailUrl, sourceKey: this.manga.sourceKey, fit: ImageFit.Cover, fill: true })
              .width('100%')
              .height(280)
              .blur(30)
          } else {
            Column()
              .width('100%')
              .height(280)
              .backgroundColor(Theme.chip(this.isDark))
          }
          Column()
            .width('100%')
            .height(280)
            .linearGradient({
              angle: 180,
              colors: [['#80000000', 0.0], [this.isDark ? '#F0101318' : '#F0F2F3F7', 1.0]],
            })

          Column() {
            Row() {
              Text('‹')
                .fontSize(30)
                .fontColor('#FFFFFF')
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  this.pathStack.pop();
                })
              Row() {
                if (this.syncing) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color('#FFFFFF')
                }
              }
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 8 })

            Row({ space: 14 }) {
              if (this.manga.thumbnailUrl === '') {
                Column() {
                  Text('📖').fontSize(30)
                }
                .width(110)
                .height(150)
                .borderRadius(10)
                .backgroundColor(Theme.chip(this.isDark))
                .justifyContent(FlexAlign.Center)
              } else {
                SmartImage({ url: this.manga.thumbnailUrl, sourceKey: this.manga.sourceKey, fit: ImageFit.Cover, fill: true })
                  .width(110)
                  .height(150)
                  .borderRadius(10)
                  .clip(true)
              }
              Column({ space: 6 }) {
                Text(this.manga.title)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.text(this.isDark))
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.manga.author !== '') {
                  Text(this.manga.author)
                    .fontSize(13)
                    .fontColor(Theme.sub(this.isDark))
                    .maxLines(1)
                }
                Text(this.manga.sourceKey === 'local' ? '本地' : Util.statusLabel(this.manga.status))
                  .fontSize(12)
                  .fontColor(Theme.primary(this.isDark))
                  .backgroundColor(Theme.chip(this.isDark))
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
        }
        .width('100%')
        .height(280)

        // 操作按钮
        Row({ space: 12 }) {
          Button(this.manga.inLibrary ? '已在书架' : '加入书架')
            .fontSize(14)
            .height(38)
            .layoutWeight(1)
            .backgroundColor(this.manga.inLibrary ? Theme.chip(this.isDark) : Theme.primary(this.isDark))
            .fontColor(this.manga.inLibrary ? Theme.text(this.isDark) : '#FFFFFF')
            .onClick(() => {
              this.toggleLibrary();
            })
          Button(this.continueChapter() !== undefined ?
            (this.chapters.some((c: ChapterRecord): boolean => c.read) ? '继续阅读' : '开始阅读') : '暂无章节')
            .fontSize(14)
            .height(38)
            .layoutWeight(1)
            .backgroundColor(Theme.chip(this.isDark))
            .fontColor(Theme.text(this.isDark))
            .onClick(() => {
              const chapter = this.continueChapter();
              if (chapter !== undefined) {
                this.openReader(chapter.id);
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12 })

        // 简介
        if (this.manga.description !== '') {
          Column() {
            Text(this.manga.description)
              .fontSize(13)
              .fontColor(Theme.sub(this.isDark))
              .maxLines(this.descExpanded ? 999 : 3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.descExpanded ? '收起' : '展开')
              .fontSize(12)
              .fontColor(Theme.primary(this.isDark))
              .margin({ top: 4 })
              .onClick(() => {
                this.descExpanded = !this.descExpanded;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 16, right: 16, top: 10 })
        }

        // AniList 追踪
        Column() {
          Text('AniList 追踪')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.text(this.isDark))
            .width('100%')
            .margin({ bottom: 8 })
          if (Settings.getAnilistToken() === '') {
            Text('在「更多」页配置 AniList 访问令牌后可追踪阅读进度')
              .fontSize(12)
              .fontColor(Theme.sub(this.isDark))
          } else if (this.track === undefined) {
            if (this.alSearching) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(Theme.primary(this.isDark))
                Text('搜索中...')
                  .fontSize(12)
                  .fontColor(Theme.sub(this.isDark))
              }
            } else {
              Text('搜索并绑定')
                .fontSize(13)
                .fontColor('#FFFFFF')
                .backgroundColor(Theme.primary(this.isDark))
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
                  .fontColor(Theme.text(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text('绑定')
                  .fontSize(12)
                  .fontColor(Theme.primary(this.isDark))
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
              .fontColor(Theme.text(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`已同步到第 ${this.track.lastChapterRead} 话`)
              .fontSize(11)
              .fontColor(Theme.sub(this.isDark))
              .margin({ top: 2 })
            Row({ space: 12 }) {
              Text('同步进度')
                .fontSize(12)
                .fontColor(Theme.primary(this.isDark))
                .backgroundColor(Theme.chip(this.isDark))
                .borderRadius(12)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .margin({ top: 8 })
                .onClick(() => {
                  this.syncTrack();
                })
              Text('解绑')
                .fontSize(12)
                .fontColor('#E05252')
                .backgroundColor(Theme.chip(this.isDark))
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
        .backgroundColor(Theme.card(this.isDark))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 12 })

        // 章节标题栏
        Row() {
          Text(`章节 ${this.chapters.length}`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.text(this.isDark))
            .layoutWeight(1)
          Text(this.sortAsc ? '正序 ↑' : '倒序 ↓')
            .fontSize(13)
            .fontColor(Theme.primary(this.isDark))
            .padding(6)
            .onClick(() => {
              this.sortAsc = !this.sortAsc;
            })
          Text('全部已读')
            .fontSize(13)
            .fontColor(Theme.primary(this.isDark))
            .padding(6)
            .onClick(() => {
              this.markAllRead();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 6 })

        // 章节列表
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(Theme.primary(this.isDark))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.chapters.length === 0) {
          Column() {
            Text('暂无章节')
              .fontSize(14)
              .fontColor(Theme.sub(this.isDark))
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.shownChapters(), (chapter: ChapterRecord) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(chapter.name)
                      .fontSize(14)
                      .fontColor(chapter.read ? Theme.sub(this.isDark) : Theme.text(this.isDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(Util.formatDate(chapter.dateUpload))
                      .fontSize(11)
                      .fontColor(Theme.sub(this.isDark))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (chapter.read) {
                    Text('已读')
                      .fontSize(11)
                      .fontColor(Theme.sub(this.isDark))
                  } else {
                    Text('NEW')
                      .fontSize(10)
                      .fontColor('#FFFFFF')
                      .backgroundColor('#E05252')
                      .borderRadius(8)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  }

                  if (this.manga.sourceKey !== 'local') {
                    if (DownloadService.isDownloaded(chapter.id)) {
                      Text('已下载')
                        .fontSize(11)
                        .fontColor(Theme.primary(this.isDark))
                        .margin({ left: 8 })
                    } else if (DownloadService.isQueued(chapter.id)) {
                      Text('队列中')
                        .fontSize(11)
                        .fontColor(Theme.sub(this.isDark))
                        .margin({ left: 8 })
                    } else {
                      Text('下载')
                        .fontSize(11)
                        .fontColor(Theme.sub(this.isDark))
                        .margin({ left: 8 })
                        .padding(4)
                        .onClick(() => {
                          this.downloadChapter(chapter);
                        })
                    }
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .onClick(() => {
                  this.openReader(chapter.id);
                })
              }
            }, (chapter: ChapterRecord) => `ch-${chapter.id}-${chapter.read}-${this.dlVersion}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .divider({
            strokeWidth: 1,
            color: Theme.divider(this.isDark),
            startMargin: 16,
            endMargin: 16,
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.bg(this.isDark))
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.bg(this.isDark))
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as DetailParams;
      this.mangaId = params !== undefined && params !== null ? params.mangaId : -1;
      this.loadAll();
    })
  }
}
