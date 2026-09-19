import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo } from '../data/Repos';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord } from '../model/Models';
import { DetailParams, ReaderParams } from '../model/RouteParams';
import { Theme } from '../common/Theme';
import { Util } from '../common/Util';

// 漫画详情页：信息 + 章节列表 + 收藏
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
  private mangaId: number = -1;

  onLibDirty(): void {
    this.reloadLocal();
  }

  private async loadAll(): Promise<void> {
    await this.reloadLocal();
    await this.syncFromSource();
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

  build() {
    NavDestination() {
      Column() {
        // 头部：封面背景 + 信息
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.manga.thumbnailUrl !== '') {
            Image(this.manga.thumbnailUrl)
              .width('100%')
              .height(280)
              .objectFit(ImageFit.Cover)
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
                Image(this.manga.thumbnailUrl)
                  .width(110)
                  .height(150)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(10)
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
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .onClick(() => {
                  this.openReader(chapter.id);
                })
              }
            }, (chapter: ChapterRecord) => `ch-${chapter.id}-${chapter.read}`)
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
