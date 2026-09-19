import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, HistoryRepo } from '../data/Repos';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord, SPage } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { Theme } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { DownloadService } from '../data/DownloadService';

// LazyForEach 数据源
class PageDataSource implements IDataSource {
  private pages: SPage[] = [];
  private listeners: DataChangeListener[] = [];

  setPages(pages: SPage[]): void {
    this.pages = pages;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): SPage {
    return this.pages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }
}

// 阅读器：翻页(LTR) / 右到左(RTL) / 条漫(Webtoon) 三模式
@Component
export struct ReaderPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageLink('libDirty') libDirty: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapter: ChapterRecord = new ChapterRecord();
  @State pages: SPage[] = [];
  @State mode: string = 'ltr';
  @State displayIndex: number = 0;
  @State currentReal: number = 0;
  @State showMenu: boolean = false;
  @State loading: boolean = true;
  @State hasPrev: boolean = false;
  @State hasNext: boolean = false;
  private dataSource: PageDataSource = new PageDataSource();
  private scroller: Scroller = new Scroller();
  private screenWidthVp: number = 360;
  private touchDownX: number = -1;
  private touchDownY: number = -1;
  private mangaId: number = -1;
  private chapterId: number = -1;

  aboutToAppear(): void {
    const screenInfo: display.Display = display.getDefaultDisplaySync();
    this.screenWidthVp = screenInfo.width / screenInfo.densityPixels;
  }

  aboutToDisappear(): void {
    this.libDirty += 1;
  }

  private async loadChapter(): Promise<void> {
    this.loading = true;
    this.showMenu = false;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const chapter = await ChapterRepo.getById(this.chapterId);
      if (chapter === undefined) {
        Util.toast(this.getUIContext(), '章节不存在');
        this.pathStack.pop();
        return;
      }
      this.chapter = chapter;
      this.mangaId = chapter.mangaId;
      const manga = await MangaRepo.get(chapter.mangaId);
      if (manga !== undefined) {
        this.manga = manga;
      }
      let pages: SPage[] = [];
      if (DownloadService.isDownloaded(chapter.id)) {
        // 离线优先：读取已下载的本地页面
        const files: string[] = DownloadService.localPages(chapter.mangaId, chapter.id);
        for (let i = 0; i < files.length; i++) {
          const p: SPage = { index: i, url: `file://${files[i]}` };
          pages.push(p);
        }
      } else {
        const source = SourceRegistry.get(this.manga.sourceKey);
        if (source === undefined) {
          throw new Error('源不可用');
        }
        pages = await source.getPageList(chapter.url);
      }
      this.pages = pages;
      this.mode = Settings.getReaderMode();
      this.currentReal = chapter.lastPageRead > 0 && chapter.lastPageRead < pages.length
        ? chapter.lastPageRead : 0;
      this.applyMode(true);
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.currentReal);
      await this.refreshNeighbors();
    } catch (e) {
      Util.toast(this.getUIContext(), `加载失败：${(e as Error).message}`);
    }
    this.loading = false;
  }

  private async refreshNeighbors(): Promise<void> {
    const all = await ChapterRepo.listByManga(this.mangaId);
    let idx = -1;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === this.chapterId) {
        idx = i;
        break;
      }
    }
    this.hasPrev = idx > 0;
    this.hasNext = idx >= 0 && idx < all.length - 1;
  }

  // 根据模式构建展示页序并恢复进度
  private applyMode(scrollToResume: boolean): void {
    if (this.mode === 'rtl') {
      this.dataSource.setPages(this.pages.slice().reverse());
      this.displayIndex = this.pages.length - 1 - this.currentReal;
    } else {
      this.dataSource.setPages(this.pages);
      this.displayIndex = this.currentReal;
    }
    if (this.mode === 'webtoon' && scrollToResume) {
      const target = this.currentReal;
      setTimeout(() => {
        this.scroller.scrollToIndex(target, false, ScrollAlign.START);
      }, 200);
    }
  }

  private displayToReal(displayIdx: number): number {
    if (this.mode === 'rtl') {
      return this.pages.length - 1 - displayIdx;
    }
    return displayIdx;
  }

  private realToDisplay(realIdx: number): number {
    if (this.mode === 'rtl') {
      return this.pages.length - 1 - realIdx;
    }
    return realIdx;
  }

  private async onSwipe(displayIdx: number): Promise<void> {
    this.displayIndex = displayIdx;
    const real = this.displayToReal(displayIdx);
    if (real !== this.currentReal) {
      this.currentReal = real;
      await this.persistProgress();
    }
  }

  private async persistProgress(): Promise<void> {
    await ChapterRepo.setLastPageRead(this.chapterId, this.currentReal);
    await HistoryRepo.upsert(this.mangaId, this.chapterId, this.currentReal);
    if (this.currentReal >= this.pages.length - 1 && !this.chapter.read) {
      this.chapter.read = true;
      await ChapterRepo.setRead(this.chapterId, true);
    }
  }

  private cycleMode(): Promise<void> {
    if (this.mode === 'ltr') {
      this.mode = 'rtl';
    } else if (this.mode === 'rtl') {
      this.mode = 'webtoon';
    } else {
      this.mode = 'ltr';
    }
    Settings.setReaderMode(this.mode);
    this.applyMode(true);
    return Promise.resolve();
  }

  private modeLabel(): string {
    if (this.mode === 'ltr') {
      return '左右翻页';
    }
    if (this.mode === 'rtl') {
      return '右→左翻页';
    }
    return '条漫模式';
  }

  private async gotoChapter(next: boolean): Promise<void> {
    const all = await ChapterRepo.listByManga(this.mangaId);
    let idx = -1;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === this.chapterId) {
        idx = i;
        break;
      }
    }
    const targetIdx = next ? idx + 1 : idx - 1;
    if (targetIdx < 0 || targetIdx >= all.length) {
      Util.toast(this.getUIContext(), next ? '已经是最后一章' : '已经是第一章');
      return;
    }
    if (next && !this.chapter.read) {
      await ChapterRepo.setRead(this.chapterId, true);
    }
    this.chapterId = all[targetIdx].id;
    await this.loadChapter();
  }

  // 翻页模式点击区域
  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      if (event.touches.length === 0) {
        return;
      }
      const down: TouchObject = event.touches[0];
      this.touchDownX = down.x;
      this.touchDownY = down.y;
    } else if (event.type === TouchType.Up) {
      if (this.touchDownX < 0 || event.changedTouches.length === 0) {
        return;
      }
      const up: TouchObject = event.changedTouches[0];
      const dx = Math.abs(up.x - this.touchDownX);
      const dy = Math.abs(up.y - this.touchDownY);
      this.touchDownX = -1;
      if (dx > 20 || dy > 20) {
        return; // 滑动，忽略
      }
      if (this.pages.length === 0) {
        return;
      }
      const zone = up.x / this.screenWidthVp;
      if (zone < 0.3) {
        // 左侧区域
        if (this.mode === 'rtl') {
          this.step(1);
        } else {
          this.step(-1);
        }
      } else if (zone > 0.7) {
        // 右侧区域
        if (this.mode === 'rtl') {
          this.step(-1);
        } else {
          this.step(1);
        }
      } else {
        this.showMenu = !this.showMenu;
      }
    }
  }

  private step(delta: number): void {
    const target = this.displayIndex + delta;
    if (target < 0) {
      Util.toast(this.getUIContext(), '已经是第一页');
      return;
    }
    if (target >= this.pages.length) {
      Util.toast(this.getUIContext(), '已经是最后一页');
      return;
    }
    this.displayIndex = target;
    this.onSwipe(target);
  }

  build() {
    NavDestination() {
      Stack() {
        // 内容区
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(Theme.primary(this.isDark))
            Text('正在加载章节…')
              .fontSize(13)
              .fontColor(Theme.sub(this.isDark))
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.mode === 'webtoon') {
          List({ scroller: this.scroller }) {
            LazyForEach(this.dataSource, (page: SPage) => {
              ListItem() {
                Image(page.url)
                  .width('100%')
                  .onClick(() => {
                    this.showMenu = !this.showMenu;
                  })
              }
            }, (page: SPage) => page.url)
          }
          .width('100%')
          .height('100%')
          .cachedCount(2)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .onScrollIndex((first: number, last: number) => {
            const real = this.displayToReal(first);
            if (real !== this.currentReal && first >= 0) {
              this.currentReal = real;
              this.persistProgress();
            }
          })
        } else {
          Swiper() {
            LazyForEach(this.dataSource, (page: SPage) => {
              Image(page.url)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
            }, (page: SPage) => page.url)
          }
          .width('100%')
          .height('100%')
          .loop(false)
          .index(this.displayIndex)
          .indicator(false)
          .onChange((index: number) => {
            this.onSwipe(index);
          })
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })
        }

        // 菜单
        if (this.showMenu) {
          Column() {
            // 顶栏
            Row() {
              Text('‹')
                .fontSize(30)
                .fontColor('#FFFFFF')
                .padding({ left: 12, right: 12 })
                .onClick(() => {
                  this.pathStack.pop();
                })
              Column() {
                Text(this.manga.title)
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.chapter.name)
                  .fontSize(11)
                  .fontColor('#CCCCCC')
                  .maxLines(1)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(`${this.currentReal + 1} / ${this.pages.length}`)
                .fontSize(13)
                .fontColor('#FFFFFF')
            }
            .width('100%')
            .padding({ left: 4, right: 16, top: 10, bottom: 10 })
            .backgroundColor('#CC000000')

            // 占位
            Column()
              .layoutWeight(1)
              .onClick(() => {
                this.showMenu = false;
              })

            // 底栏
            Row() {
              Text(this.hasPrev ? '上一章' : '─')
                .fontSize(14)
                .fontColor(this.hasPrev ? '#FFFFFF' : '#666666')
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding(12)
                .onClick(() => {
                  if (this.hasPrev) {
                    this.gotoChapter(false);
                  }
                })
              Text(this.modeLabel())
                .fontSize(14)
                .fontColor('#FFFFFF')
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding(12)
                .onClick(() => {
                  this.cycleMode();
                })
              Text(this.hasNext ? '下一章' : '─')
                .fontSize(14)
                .fontColor(this.hasNext ? '#FFFFFF' : '#666666')
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .padding(12)
                .onClick(() => {
                  if (this.hasNext) {
                    this.gotoChapter(true);
                  }
                })
            }
            .width('100%')
            .backgroundColor('#CC000000')
          }
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.readerBg(this.isDark))
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.readerBg(this.isDark))
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
