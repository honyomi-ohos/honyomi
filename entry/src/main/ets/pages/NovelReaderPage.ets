import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, HistoryRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { DownloadService } from '../data/DownloadService';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { AppIcon } from './components/AppIcon';
import { fileIo as fs } from '@kit.CoreFileKit';

// 小说阅读：滚动正文。进度记为滚动千分比 0–1000。
@Component
export struct NovelReaderPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapter: ChapterRecord = new ChapterRecord();
  @State body: string = '';
  @State html: boolean = false;
  @State loading: boolean = true;
  @State showStyle: boolean = false;
  @State fontSize: number = 18;
  @State lineHeight: number = 32;
  @State prevId: number = 0;
  @State nextId: number = 0;
  private mangaId: number = -1;
  private chapterId: number = -1;
  private scroller: Scroller = new Scroller();
  private scrollY: number = 0;
  private contentH: number = 0;
  private viewH: number = 0;
  private restored: boolean = false;
  private permille: number = 0;

  aboutToDisappear(): void {
    this.persist();
    ReadingStatsRepo.flush();
  }

  private async loadChapter(): Promise<void> {
    this.loading = true;
    this.restored = false;
    this.body = '';
    ReadingStatsRepo.flush();
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const chapter = await ChapterRepo.getById(this.chapterId);
      if (chapter === undefined) {
        Util.toastRes(this.getUIContext(), $r('app.string.reader_chapter_not_found'));
        this.pathStack.pop();
        return;
      }
      this.chapter = chapter;
      this.mangaId = chapter.mangaId;
      this.permille = chapter.lastPageRead > 0 && chapter.lastPageRead <= 1000 ? chapter.lastPageRead : 0;
      const manga = await MangaRepo.get(chapter.mangaId);
      if (manga !== undefined) {
        this.manga = manga;
      }
      const local = DownloadService.localText(chapter.mangaId, chapter.id);
      let text = '';
      if (local !== '') {
        text = fs.readTextSync(local);
      } else {
        const source = SourceRegistry.get(this.manga.sourceKey);
        if (source === undefined) {
          throw new Error('源不可用');
        }
        text = await source.getChapterText(chapter.url);
      }
      if (text === '') {
        throw new Error('章节没有正文');
      }
      this.html = NovelReaderPage.looksLikeHtml(text);
      this.body = text;
      this.fontSize = Settings.getNovelFontSize();
      this.lineHeight = Settings.getNovelLineHeight();
      await this.loadNeighbors();
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.permille);
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'), [(e as Error).message]);
    }
    this.loading = false;
  }

  private async loadNeighbors(): Promise<void> {
    const list = await ChapterRepo.listByManga(this.mangaId);
    let idx = -1;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === this.chapterId) {
        idx = i;
      }
    }
    this.prevId = idx > 0 ? list[idx - 1].id : 0;
    this.nextId = idx >= 0 && idx < list.length - 1 ? list[idx + 1].id : 0;
  }

  private restoreOnce(): void {
    if (this.restored || this.permille <= 0 || this.contentH <= this.viewH || this.viewH <= 0) {
      return;
    }
    const range = this.contentH - this.viewH;
    this.scroller.scrollTo({ xOffset: 0, yOffset: range * this.permille / 1000, animation: false });
    this.restored = true;
  }

  private captureOffset(y: number): void {
    this.scrollY = y;
    ReadingStatsRepo.tick();
    const range = this.contentH - this.viewH;
    if (range <= 0) {
      this.permille = 1000;
      return;
    }
    let value = Math.round(y / range * 1000);
    if (value < 0) {
      value = 0;
    }
    if (value > 1000) {
      value = 1000;
    }
    this.permille = value;
  }

  private persist(): void {
    if (this.chapterId <= 0) {
      return;
    }
    ChapterRepo.setLastPageRead(this.chapterId, this.permille).catch(() => {
    });
    HistoryRepo.upsert(this.mangaId, this.chapterId, this.permille).catch(() => {
    });
    if (this.permille >= 950) {
      ChapterRepo.setRead(this.chapterId, true).catch(() => {
      });
    }
  }

  private openChapter(id: number): void {
    if (id <= 0) {
      return;
    }
    this.persist();
    this.chapterId = id;
    this.loadChapter();
  }

  private static looksLikeHtml(text: string): boolean {
    const head = text.substring(0, 240).toLowerCase();
    return head.indexOf('<p') >= 0 || head.indexOf('<br') >= 0 || head.indexOf('<div') >= 0 ||
      head.indexOf('<html') >= 0;
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 24 })
            .onClick(() => {
              this.pathStack.pop();
            })
          Column() {
            Text(this.manga.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.chapter.name)
              .fontSize(12)
              .fontColor(this.pal.sub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 8 })
          Text('Aa')
            .fontSize(16)
            .fontColor(this.showStyle ? '#FFFFFF' : this.pal.text)
            .backgroundColor(this.showStyle ? this.pal.primary : this.pal.chip)
            .borderRadius(14)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .onClick(() => {
              this.showStyle = !this.showStyle;
            })
        }
        .width('100%')
        .padding({ left: 12, right: 16, top: this.statusBarH + 8, bottom: 8 })

        if (this.showStyle) {
          Column() {
            Text($r('app.string.novel_font_size'))
              .fontSize(12)
              .fontColor(this.pal.sub)
              .width('100%')
            Slider({ value: this.fontSize, min: 14, max: 32, step: 1 })
              .selectedColor(this.pal.primary)
              .onChange((v: number) => {
                this.fontSize = Math.round(v);
                Settings.setNovelFontSize(this.fontSize);
                this.restored = true;
              })
            Text($r('app.string.novel_line_height'))
              .fontSize(12)
              .fontColor(this.pal.sub)
              .width('100%')
            Slider({ value: this.lineHeight, min: 20, max: 56, step: 1 })
              .selectedColor(this.pal.primary)
              .onChange((v: number) => {
                this.lineHeight = Math.round(v);
                Settings.setNovelLineHeight(this.lineHeight);
                this.restored = true;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
        }

        if (this.loading) {
          Column() {
            LoadingProgress().width(36).height(36).color(this.pal.primary)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.body === '') {
          Column() {
            Text($r('app.string.novel_empty'))
              .fontSize(14)
              .fontColor(this.pal.sub)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll(this.scroller) {
            Column() {
              if (this.html) {
                RichText(this.body)
                  .width('100%')
              } else {
                Text(this.body)
                  .fontSize(this.fontSize)
                  .lineHeight(this.lineHeight)
                  .fontColor(this.pal.text)
                  .width('100%')
              }
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 8, bottom: 24 })
            .onAreaChange((_old: Area, neu: Area) => {
              const h = neu.height;
              if (typeof h === 'number') {
                this.contentH = h;
                this.restoreOnce();
              }
            })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .onAreaChange((_old: Area, neu: Area) => {
            const h = neu.height;
            if (typeof h === 'number') {
              this.viewH = h;
              this.restoreOnce();
            }
          })
          .onScroll((_x: number, y: number) => {
            this.captureOffset(y);
          })
          .onScrollStop(() => {
            this.persist();
          })
        }

        Row() {
          Text($r('app.string.novel_prev'))
            .fontSize(14)
            .fontColor(this.prevId > 0 ? this.pal.primary : this.pal.sub)
            .onClick(() => {
              this.openChapter(this.prevId);
            })
          Blank()
          Text(`${Math.round(this.permille / 10)}%`)
            .fontSize(12)
            .fontColor(this.pal.sub)
          Blank()
          Text($r('app.string.novel_next'))
            .fontSize(14)
            .fontColor(this.nextId > 0 ? this.pal.primary : this.pal.sub)
            .onClick(() => {
              this.openChapter(this.nextId);
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: this.navBarH + 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as ReaderParams;
      if (params !== undefined && params !== null) {
        this.mangaId = params.mangaId;
        this.chapterId = params.chapterId;
      }
      this.loadChapter();
    })
  }
}
