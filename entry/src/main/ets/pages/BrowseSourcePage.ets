import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { SourceRegistry, Source } from '../source/Source';
import { LocalSource } from '../source/LocalSource';
import { MangaRecord, SManga, MangasPage } from '../model/Models';
import { BrowseSourceParams, DetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { MangaCard } from './components/MangaCard';
import { MangaSkeletonGrid } from './components/MangaSkeletonGrid';
import { InputDialog } from './components/Dialogs';
import { EmptyScreen } from './components/EmptyScreen';
import { AppIcon } from './components/AppIcon';

// 单源浏览页（图源 Tab 点进某个源）：顶栏返回 + 搜索 + 热门/最新模式 + 结果网格
@Component
export struct BrowseSourcePage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State sourceKey: string = '';
  @State mode: string = 'popular';
  @State query: string = '';
  @State searchOpen: boolean = false;
  @State results: MangaRecord[] = [];
  @State searching: boolean = false;
  @State page: number = 1;
  @State hasNextPage: boolean = false;
  @State loadingMore: boolean = false;
  @State contentW: number = 0;
  private pickedUris: string[] = [];

  currentSource(): Source | undefined {
    return SourceRegistry.get(this.sourceKey);
  }

  // 结果网格列数：手机双列，平板/横屏按约 160vp 一卡自适应增加列数
  private gridColumns(): number {
    const w = this.contentW > 0 ? this.contentW : 360;
    return Math.max(2, Math.floor((w - 32 - 12) / 160));
  }

  private columnsTpl(): string {
    let tpl = '';
    for (let i = 0; i < this.gridColumns(); i++) {
      tpl += '1fr ';
    }
    return tpl.trim();
  }

  // 当前模式下的列表页（最新模式仅在源支持时生效）
  private fetchPage(source: Source, page: number): Promise<MangasPage> {
    if (this.mode === 'latest' && source.supportsLatest) {
      return source.getLatestManga(page);
    }
    return source.getPopularManga(page);
  }

  async loadFirst(): Promise<void> {
    const source = this.currentSource();
    if (source === undefined) {
      return;
    }
    this.searching = true;
    this.results = [];
    this.page = 1;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const result = await this.fetchPage(source, 1);
      this.results = await this.toRecords(source.key, result.mangas);
      this.hasNextPage = result.hasNextPage;
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_load_failed'), [(e as Error).message]);
    }
    this.searching = false;
  }

  async search(): Promise<void> {
    const source = this.currentSource();
    if (source === undefined) {
      return;
    }
    this.searching = true;
    this.results = [];
    this.page = 1;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const q = this.query.trim();
      const result = q === '' ? await source.getPopularManga(1) : await source.getSearchManga(1, q);
      this.results = await this.toRecords(source.key, result.mangas);
      this.hasNextPage = result.hasNextPage;
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_search_failed'), [(e as Error).message]);
    }
    this.searching = false;
  }

  async loadMore(): Promise<void> {
    const source = this.currentSource();
    if (source === undefined || this.loadingMore || !this.hasNextPage) {
      return;
    }
    this.loadingMore = true;
    try {
      const nextPage = this.page + 1;
      const q = this.query.trim();
      const result = q === '' ? await this.fetchPage(source, nextPage) :
        await source.getSearchManga(nextPage, q);
      const more = await this.toRecords(source.key, result.mangas);
      this.results = this.results.concat(more);
      this.page = nextPage;
      this.hasNextPage = result.hasNextPage;
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_load_more_failed'));
    }
    this.loadingMore = false;
  }

  async toRecords(sourceKey: string, mangas: SManga[]): Promise<MangaRecord[]> {
    const records: MangaRecord[] = [];
    for (const m of mangas) {
      const record = new MangaRecord();
      record.sourceKey = sourceKey;
      record.url = m.key;
      record.title = m.title;
      record.thumbnailUrl = m.coverUrl;
      record.author = m.author;
      record.description = m.description;
      record.genre = m.genre;
      record.status = m.status;
      records.push(record);
    }
    return records;
  }

  async openDetail(record: MangaRecord): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const id = await MangaRepo.upsertFromSource(record.sourceKey, this.toSManga(record));
      const params: DetailParams = { mangaId: id };
      this.pathStack.pushPathByName('MangaDetail', params);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_open_detail_failed'));
    }
  }

  toSManga(record: MangaRecord): SManga {
    const m: SManga = {
      key: record.url,
      title: record.title,
      coverUrl: record.thumbnailUrl,
      author: record.author,
      description: record.description,
      genre: record.genre,
      status: record.status,
    };
    return m;
  }

  async pickImportFiles(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 50;
      options.fileSuffixFilters = ['.zip', '.cbz'];
      const docPicker = new picker.DocumentViewPicker();
      const uris: Array<string> = await docPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      this.pickedUris = uris;
      this.showImportDialog();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_pick_file_failed'));
    }
  }

  private showImportDialog(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.browse_import_title', this.pickedUris.length),
        placeholder: $r('app.string.browse_manga_name_hint'),
        onConfirm: (text: string): void => {
          this.doImport(text.trim());
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async doImport(title: string): Promise<void> {
    if (title === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_input_name'));
      return;
    }
    const source = SourceRegistry.get('local');
    if (source === undefined) {
      return;
    }
    const local = source as LocalSource;
    try {
      const count = await local.importFiles(this.pickedUris, title);
      Util.toastRes(this.getUIContext(), $r('app.string.browse_import_done'), [count]);
      await this.loadFirst();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_import_failed'), [(e as Error).message]);
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 24 })
            .onClick(() => {
              this.pathStack.pop();
            })
          Text(this.currentSource() !== undefined ? (this.currentSource() as Source).name : '')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .margin({ left: 8 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.sourceKey === 'local') {
            Text($r('app.string.browse_import'))
              .fontSize(13)
              .fontColor(this.pal.primary)
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                this.pickImportFiles();
              })
          } else if (this.searchOpen) {
            AppIcon({ name: 'close', iconSize: 20 })
              .padding({ left: 10, right: 10 })
              .onClick(() => {
                this.searchOpen = false;
                this.query = '';
                this.loadFirst();
              })
          } else {
            AppIcon({ name: 'search', iconSize: 20 })
              .padding({ left: 10, right: 10 })
              .onClick(() => {
                this.searchOpen = true;
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.statusBarH + 10, bottom: 8 })

        // 搜索栏
        if (this.searchOpen && this.sourceKey !== 'local') {
          Row({ space: 8 }) {
            TextInput({ placeholder: $r('app.string.browse_search_hint') })
              .layoutWeight(1)
              .height(38)
              .backgroundColor(this.pal.card)
              .enterKeyType(EnterKeyType.Search)
              .onChange((value: string) => {
                this.query = value;
              })
              .onSubmit(() => {
                this.search();
              })
            Button($r('app.string.common_search'))
              .fontSize(14)
              .height(38)
              .backgroundColor(this.pal.primary)
              .onClick(() => {
                this.search();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
        }

        // 模式切换（仅支持最新更新的源显示）
        if (this.sourceKey !== 'local' && this.currentSource()?.supportsLatest === true) {
          Row({ space: 8 }) {
            Text($r('app.string.browse_popular'))
              .fontSize(13)
              .fontColor(this.mode === 'popular' ? '#FFFFFF' : this.pal.sub)
              .backgroundColor(this.mode === 'popular' ? this.pal.primary : this.pal.bg)
              .borderRadius(12)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .onClick(() => {
                if (this.mode !== 'popular') {
                  this.mode = 'popular';
                  this.loadFirst();
                }
              })
            Text($r('app.string.browse_latest'))
              .fontSize(13)
              .fontColor(this.mode === 'latest' ? '#FFFFFF' : this.pal.sub)
              .backgroundColor(this.mode === 'latest' ? this.pal.primary : this.pal.bg)
              .borderRadius(12)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
              .onClick(() => {
                if (this.mode !== 'latest') {
                  this.mode = 'latest';
                  this.loadFirst();
                }
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
        }

        // 结果网格
        if (this.currentSource() === undefined) {
          Column() {
            EmptyScreen({ message: $r('app.string.browse_source_missing') })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.searching) {
          // 首次加载骨架屏（与结果网格同布局的占位卡片）
          MangaSkeletonGrid({ columns: this.gridColumns() })
        } else if (this.results.length === 0) {
          Column() {
            EmptyScreen({
              message: this.sourceKey === 'local' ? $r('app.string.browse_local_empty') : $r('app.string.browse_no_results'),
            })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.results, (record: MangaRecord) => {
              GridItem() {
                MangaCard({
                  record: record,
                  onCardClick: (r: MangaRecord): void => {
                    this.openDetail(r);
                  },
                })
              }
            }, (record: MangaRecord) => `bs-${record.sourceKey}-${record.url}`)
          }
          .columnsTemplate(this.columnsTpl())
          .columnsGap(12)
          .rowsGap(16)
          .padding({ left: 16, right: 16, top: 4 })
          .contentEndOffset(this.navBarH + 16)
          .layoutWeight(1)
          .onReachEnd(() => {
            this.loadMore();
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
      .onAreaChange((_old: Area, newArea: Area) => {
        const w = newArea.width;
        if (typeof w === 'number') {
          this.contentW = w;
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as BrowseSourceParams;
      this.sourceKey = params !== undefined && params !== null ? params.sourceKey : '';
      this.mode = params !== undefined && params !== null && params.mode === 'latest' ? 'latest' : 'popular';
      this.loadFirst();
    })
  }
}
