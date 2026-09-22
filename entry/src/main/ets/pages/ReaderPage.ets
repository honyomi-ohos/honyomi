import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, HistoryRepo } from '../data/Repos';
import { SourceRegistry } from '../source/Source';
import { MangaRecord, ChapterRecord, SPage } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { Theme, ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { DownloadService } from '../data/DownloadService';
import { SmartImage } from './components/SmartImage';
import { ComicStripViewer } from './components/ComicStripViewer';
import { AppIconRes, AppIcon } from './components/AppIcon';
import { SwitchRow } from './components/Prefs';

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
// 底栏对齐 Mihon：章节导航行（圆形上/下一章按钮 + 页码胶囊 Slider）+ 设置行（模式/旋转/裁边/设置）
@Component
export struct ReaderPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageLink('libDirty') libDirty: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapter: ChapterRecord = new ChapterRecord();
  @State pages: SPage[] = [];
  @State mode: string = 'ltr';
  @State displayIndex: number = 0;
  @State currentReal: number = 0;
  @State showMenu: boolean = false;
  @State showSettings: boolean = false;
  @State loading: boolean = true;
  @State hasPrev: boolean = false;
  @State hasNext: boolean = false;
  @State crop: boolean = false;
  @State readerTheme: number = 3;
  @State brightLv: number = 0;
  @State showPageNumber: boolean = true;
  @State orientation: string = 'free';
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
    this.crop = Settings.getReaderCrop();
    this.readerTheme = Settings.getReaderTheme();
    this.brightLv = Settings.getReaderBrightness();
    this.showPageNumber = Settings.getReaderShowPageNumber();
    this.orientation = Settings.getReaderOrientation();
    this.applyOrientation();
    this.applyBrightness();
  }

  aboutToDisappear(): void {
    this.libDirty += 1;
    // 还原窗口方向与亮度
    const ctx = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(ctx).then((win: window.Window) => {
      win.setPreferredOrientation(window.Orientation.UNSPECIFIED).catch(() => {
      });
      win.setWindowBrightness(0).catch(() => {
      });
    }).catch(() => {
    });
  }

  private applyOrientation(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(ctx).then((win: window.Window) => {
      let target: window.Orientation = window.Orientation.UNSPECIFIED;
      if (this.orientation === 'portrait') {
        target = window.Orientation.PORTRAIT;
      } else if (this.orientation === 'landscape') {
        target = window.Orientation.LANDSCAPE;
      }
      win.setPreferredOrientation(target).catch(() => {
      });
    }).catch(() => {
    });
  }

  private applyBrightness(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(ctx).then((win: window.Window) => {
      win.setWindowBrightness(this.brightLv).catch(() => {
      });
    }).catch(() => {
    });
  }

  private async loadChapter(): Promise<void> {
    this.loading = true;
    this.showMenu = false;
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
      Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'), [(e as Error).message]);
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

  private setMode(mode: string): void {
    this.mode = mode;
    Settings.setReaderMode(mode);
    this.applyMode(true);
  }

  private modeIcon(): string {
    if (this.mode === 'rtl') {
      return 'reader_rtl';
    }
    if (this.mode === 'webtoon') {
      return 'reader_webtoon';
    }
    return 'reader_ltr';
  }

  private selectMode(): void {
    const sheets: SheetInfo[] = [];
    sheets.push({
      title: $r('app.string.reader_mode_ltr'),
      action: (): void => {
        this.setMode('ltr');
      }
    });
    sheets.push({
      title: $r('app.string.reader_mode_rtl'),
      action: (): void => {
        this.setMode('rtl');
      }
    });
    sheets.push({
      title: $r('app.string.reader_mode_webtoon'),
      action: (): void => {
        this.setMode('webtoon');
      }
    });
    const opts: ActionSheetOptions = {
      title: $r('app.string.reader_reading_mode'),
      message: '',
      sheets: sheets
    };
    this.getUIContext().showActionSheet(opts);
  }

  private selectOrientation(): void {
    const labels: ResourceStr[] = [$r('app.string.reader_orientation_free'), $r('app.string.reader_orientation_portrait'), $r('app.string.reader_orientation_landscape')];
    const values: string[] = ['free', 'portrait', 'landscape'];
    const sheets: SheetInfo[] = [];
    for (let i = 0; i < values.length; i++) {
      const v: string = values[i];
      sheets.push({
        title: labels[i],
        action: (): void => {
          this.orientation = v;
          Settings.setReaderOrientation(v);
          this.applyOrientation();
        }
      });
    }
    const opts: ActionSheetOptions = {
      title: $r('app.string.reader_screen_orientation'),
      message: '',
      sheets: sheets
    };
    this.getUIContext().showActionSheet(opts);
  }

  private toggleCrop(): void {
    this.crop = !this.crop;
    Settings.setReaderCrop(this.crop);
  }

  // Slider 跳页（按真实页序）
  private jumpToReal(real: number): void {
    if (real < 0 || real >= this.pages.length) {
      return;
    }
    const display = this.realToDisplay(real);
    this.displayIndex = display;
    if (this.mode === 'webtoon') {
      this.scroller.scrollToIndex(display, false, ScrollAlign.START);
      this.currentReal = real;
      this.persistProgress();
    } else {
      this.onSwipe(display);
    }
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
      Util.toastRes(this.getUIContext(), next ? $r('app.string.reader_last_chapter') : $r('app.string.reader_first_chapter'));
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
      Util.toastRes(this.getUIContext(), $r('app.string.reader_first_page'));
      return;
    }
    if (target >= this.pages.length) {
      Util.toastRes(this.getUIContext(), $r('app.string.reader_last_page'));
      return;
    }
    this.displayIndex = target;
    this.onSwipe(target);
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        // 内容区
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(this.pal.primary)
            Text($r('app.string.reader_loading_chapter'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.mode === 'webtoon') {
          // 条漫模式：PixelMap 直绘的无限竖向滚动（防防盗链拦截 + 内存受控）
          ComicStripViewer({
            pages: this.pages,
            sourceKey: this.manga.sourceKey,
            initialIndex: this.currentReal,
            isDark: this.isDark,
            scroller: this.scroller,
            onTap: (): void => {
              this.showMenu = !this.showMenu;
            },
            onPageVisible: (index: number): void => {
              this.displayIndex = index;
              const real = this.displayToReal(index);
              if (real !== this.currentReal && index >= 0) {
                this.currentReal = real;
                this.persistProgress();
              }
            }
          })
            .width('100%')
            .height('100%')
        } else {
          Swiper() {
            LazyForEach(this.dataSource, (page: SPage) => {
              SmartImage({
                url: page.url,
                sourceKey: this.manga.sourceKey,
                fit: this.crop ? ImageFit.Cover : ImageFit.Contain,
                fill: true
              })
                .width('100%')
                .height('100%')
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

        // 页码指示（菜单收起时）
        if (!this.showMenu && !this.loading && this.pages.length > 0 && this.showPageNumber) {
          Text(`${this.currentReal + 1}/${this.pages.length}`)
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor('#66000000')
            .margin({ left: 16, top: 16, right: 16, bottom: this.navBarH + 16 })
        }

        // 菜单
        if (this.showMenu) {
          Column() {
            // 顶栏
            Row() {
              AppIcon({ name: 'arrow_back', iconSize: 24, tint: '#FFFFFF' })
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
            }
            .width('100%')
            .padding({ left: 4, right: 16, top: this.statusBarH + 10, bottom: 10 })
            .backgroundColor('#CC000000')

            // 占位
            Column()
              .layoutWeight(1)
              .onClick(() => {
                this.showMenu = false;
              })

            // 底栏：章节导航行 + 设置行（对齐 Mihon ReaderAppBars）
            Column({ space: 8 }) {
              // 章节导航行
              Row({ space: 12 }) {
                // 上一章
                Column() {
                  Image(AppIconRes.get('skip_previous'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(44)
                .height(44)
                .borderRadius(22)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#33FFFFFF')
                .opacity(this.hasPrev ? 1 : 0.4)
                .onClick(() => {
                  if (this.hasPrev) {
                    this.gotoChapter(false);
                  }
                })

                // 页码胶囊：当前页 + Slider + 总页数
                if (this.pages.length > 0) {
                  Row() {
                    Text(`${this.currentReal + 1}`)
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .width(24)
                      .textAlign(TextAlign.End)
                    Slider({
                      value: this.currentReal + 1,
                      min: 1,
                      max: this.pages.length > 1 ? this.pages.length : 2,
                      step: 1,
                      style: SliderStyle.OutSet
                    })
                      .layoutWeight(1)
                      .blockColor('#FFFFFF')
                      .selectedColor('#88FFFFFF')
                      .trackColor('#33FFFFFF')
                      .margin({ left: 8, right: 8 })
                      .onChange((value: number, mode: SliderChangeMode) => {
                        if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                          this.jumpToReal(Math.round(value) - 1);
                        }
                      })
                    Text(`${this.pages.length}`)
                      .fontSize(13)
                      .fontColor('#FFFFFF')
                      .width(24)
                  }
                  .layoutWeight(1)
                  .height(44)
                  .borderRadius(22)
                  .backgroundColor('#33FFFFFF')
                  .padding({ left: 14, right: 14 })
                } else {
                  Column().layoutWeight(1)
                }

                // 下一章
                Column() {
                  Image(AppIconRes.get('skip_next'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(44)
                .height(44)
                .borderRadius(22)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#33FFFFFF')
                .opacity(this.hasNext ? 1 : 0.4)
                .onClick(() => {
                  if (this.hasNext) {
                    this.gotoChapter(true);
                  }
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16 })

              // 设置行：阅读模式 / 旋转 / 裁边 / 设置
              Row() {
                Column() {
                  Image(AppIconRes.get(this.modeIcon()))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.selectMode();
                })

                Column() {
                  Image(AppIconRes.get('screen_rotation'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.selectOrientation();
                })

                Column() {
                  Image(AppIconRes.get(this.crop ? 'crop' : 'crop_off'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.toggleCrop();
                })

                Column() {
                  Image(AppIconRes.get('settings'))
                    .width(24)
                    .height(24)
                    .fillColor('#FFFFFF')
                }
                .width(48)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.showSettings = true;
                })
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.SpaceEvenly)
              .backgroundColor('#CC000000')
            }
            .width('100%')
            .padding({ top: 8, bottom: this.navBarH + 8 })
            .backgroundColor('#CC000000')
          }
          .width('100%')
          .height('100%')
          .bindSheet(this.showSettings, this.settingsSheet(), {
            height: 380,
            dragBar: true,
            showClose: false,
            onDisappear: (): void => {
              this.showSettings = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.readerBg(this.readerTheme, this.isDark))
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

  // 更多设置面板：背景色 / 显示页码 / 亮度
  @Builder
  settingsSheet() {
    Column({ space: 0 }) {
      Text($r('app.string.reader_settings'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      // 背景色
      Column({ space: 8 }) {
        Text($r('app.string.reader_background'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
        Row({ space: 8 }) {
          this.themeChip($r('app.string.reader_theme_auto'), 3)
          this.themeChip($r('app.string.reader_theme_white'), 0)
          this.themeChip($r('app.string.reader_theme_gray'), 2)
          this.themeChip($r('app.string.reader_theme_black'), 1)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })

      // 显示页码
      SwitchRow({
        title: $r('app.string.reader_show_page_number'),
        isOn: this.showPageNumber,
        onChange: (value: boolean): void => {
          this.showPageNumber = value;
          Settings.setReaderShowPageNumber(value);
        }
      })

      Divider().color(this.pal.divider).margin({ top: 4, bottom: 4 })

      // 亮度
      Row() {
        Text($r('app.string.reader_brightness'))
          .fontSize(16)
          .fontColor(this.pal.text)
          .width(64)
        Slider({ value: this.brightLv, min: 0, max: 1, step: 0.05 })
          .layoutWeight(1)
          .blockColor(this.pal.primary)
          .selectedColor(this.pal.primary)
          .trackColor(this.pal.divider)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.brightLv = Math.round(value * 20) / 20;
              Settings.setReaderBrightness(this.brightLv);
              this.applyBrightness();
            }
          })
        Text(this.brightLv === 0 ? $r('app.string.reader_auto') : `${Math.round(this.brightLv * 100)}%`)
          .fontSize(12)
          .fontColor(this.pal.sub)
          .width(44)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })

      Column().height(16)
    }
    .width('100%')
    .backgroundColor(this.pal.bg)
  }

  @Builder
  themeChip(label: ResourceStr, value: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.readerTheme === value ? '#FFFFFF' : this.pal.text)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.readerTheme === value ? this.pal.primary : this.pal.chip)
      .onClick(() => {
        this.readerTheme = value;
        Settings.setReaderTheme(value);
      })
  }
}
