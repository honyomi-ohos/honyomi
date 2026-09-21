import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { SourceRegistry, Source } from '../source/Source';
import { LocalSource } from '../source/LocalSource';
import { MangaRecord, SManga, MangasPage } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { MangaCard } from './components/MangaCard';
import { InputDialog } from './components/Dialogs';
import { EmptyScreen } from './components/EmptyScreen';

// 浏览页：源选择 + 搜索 + 本地导入 + 插件管理入口
@Component
export struct BrowsePage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('pluginsDirty') @Watch('onPluginsChanged') pluginsDirty: number = 0;
  @State sources: Source[] = [];
  @State selectedSource: string = 'mangadex';
  @State query: string = '';
  @State mode: string = 'popular'; // popular | latest
  @State results: MangaRecord[] = [];
  @State searching: boolean = false;
  @State page: number = 1;
  @State hasNextPage: boolean = false;
  @State loadingMore: boolean = false;
  private pickedUris: string[] = [];

  aboutToAppear(): void {
    this.refreshSources();
    this.loadPopular();
  }

  // 插件安装/启停后刷新源列表
  onPluginsChanged(): void {
    this.refreshSources();
  }

  private refreshSources(): void {
    this.sources = SourceRegistry.all();
    const cur = SourceRegistry.get(this.selectedSource);
    if (cur === undefined) {
      const mangadex = SourceRegistry.get('mangadex');
      const fallback = mangadex !== undefined ? mangadex :
        (this.sources.length > 0 ? this.sources[0] : undefined);
      if (fallback !== undefined) {
        this.selectedSource = fallback.key;
        this.loadPopular();
      } else {
        this.selectedSource = 'local';
      }
    }
  }

  currentSource(): Source | undefined {
    return SourceRegistry.get(this.selectedSource);
  }

  // 当前模式下的列表页（最新模式仅在源支持时生效）
  private fetchPage(source: Source, page: number): Promise<MangasPage> {
    if (this.mode === 'latest' && source.supportsLatest) {
      return source.getLatestManga(page);
    }
    return source.getPopularManga(page);
  }

  async loadPopular(): Promise<void> {
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
    const source = this.currentSource();
    if (source === undefined) {
      return;
    }
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
      Util.toastRes(this.getUIContext(), $r('app.string.browse_import_done', count));
      await this.loadPopular();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_import_failed'), [(e as Error).message]);
    }
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text($r('app.string.browse_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        if (this.selectedSource === 'local') {
          Button($r('app.string.browse_import'))
            .fontSize(14)
            .height(32)
            .backgroundColor(this.pal.primary)
            .onClick(() => {
              this.pickImportFiles();
            })
        }
        Text($r('app.string.browse_plugins'))
          .fontSize(13)
          .fontColor(this.pal.primary)
          .padding({ left: 12, right: 4 })
          .onClick(() => {
            this.pathStack.pushPathByName('Plugins', null);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 源选择
      Row({ space: 8 }) {
        ForEach(this.sources, (source: Source) => {
          Text(source.key === 'local' ? $r('app.string.browse_local_source_name') : source.name)
            .fontSize(13)
            .fontColor(this.selectedSource === source.key ? '#FFFFFF' : this.pal.text)
            .backgroundColor(this.selectedSource === source.key ? this.pal.primary : this.pal.chip)
            .borderRadius(14)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => {
              if (this.selectedSource !== source.key) {
                this.selectedSource = source.key;
                this.query = '';
                this.loadPopular();
              }
            })
        }, (source: Source) => `src-${source.key}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 模式切换（仅支持最新更新的源显示）
      if (this.selectedSource !== 'local' && this.currentSource()?.supportsLatest === true) {
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
                this.loadPopular();
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
                this.loadPopular();
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }

      // 搜索栏
      if (this.selectedSource !== 'local') {
        Row({ space: 8 }) {
          TextInput({ placeholder: $r('app.string.browse_search_hint') })
            .layoutWeight(1)
            .height(38)
            .backgroundColor(this.pal.card)
            .onChange((value: string) => {
              this.query = value;
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

      // 结果网格
      if (this.searching) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.pal.primary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.results.length === 0) {
        Column() {
          EmptyScreen({
            message: this.selectedSource === 'local' ? $r('app.string.browse_local_empty') : $r('app.string.browse_no_results'),
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
          }, (record: MangaRecord) => `browse-${record.sourceKey}-${record.url}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(16)
        .padding({ left: 16, right: 16, top: 4 })
        .contentEndOffset(this.navBarH + 76)
        .layoutWeight(1)
        .onReachEnd(() => {
          this.loadMore();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }
}
