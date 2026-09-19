import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { SourceRegistry, Source } from '../source/Source';
import { LocalSource } from '../source/LocalSource';
import { MangaRecord, SManga, DetailParams } from '../model/Models';
import { Theme } from '../common/Theme';
import { Util } from '../common/Util';
import { MangaCard } from './components/MangaCard';
import { InputDialog } from './components/Dialogs';

// 浏览页：源选择 + 搜索 + 本地导入
@Component
export struct BrowsePage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @State sources: Source[] = [];
  @State selectedSource: string = 'mangadex';
  @State query: string = '';
  @State results: MangaRecord[] = [];
  @State searching: boolean = false;
  @State page: number = 1;
  @State hasNextPage: boolean = false;
  @State loadingMore: boolean = false;
  private pickedUris: string[] = [];

  aboutToAppear(): void {
    this.sources = SourceRegistry.all();
    this.loadPopular();
  }

  currentSource(): Source | undefined {
    return SourceRegistry.get(this.selectedSource);
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
      const result = await source.getPopularManga(1);
      this.results = await this.toRecords(source.key, result.mangas);
      this.hasNextPage = result.hasNextPage;
    } catch (e) {
      Util.toast(this.getUIContext(), `加载失败：${(e as Error).message}`);
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
      Util.toast(this.getUIContext(), `搜索失败：${(e as Error).message}`);
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
      const result = q === '' ? await source.getPopularManga(nextPage) : await source.getSearchManga(nextPage, q);
      const more = await this.toRecords(source.key, result.mangas);
      this.results = this.results.concat(more);
      this.page = nextPage;
      this.hasNextPage = result.hasNextPage;
    } catch (e) {
      Util.toast(this.getUIContext(), '加载更多失败');
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
      Util.toast(this.getUIContext(), '打开详情失败');
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
      Util.toast(this.getUIContext(), '选择文件失败');
    }
  }

  private showImportDialog(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: `导入 ${this.pickedUris.length} 个文件到漫画`,
        placeholder: '漫画名称（将创建本地漫画）',
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
      Util.toast(this.getUIContext(), '请输入漫画名称');
      return;
    }
    const source = SourceRegistry.get('local');
    if (source === undefined) {
      return;
    }
    const local = source as LocalSource;
    try {
      const count = await local.importFiles(this.pickedUris, title);
      Util.toast(this.getUIContext(), `已导入 ${count} 个章节文件`);
      await this.loadPopular();
    } catch (e) {
      Util.toast(this.getUIContext(), `导入失败：${(e as Error).message}`);
    }
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Text('浏览')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text(this.isDark))
          .layoutWeight(1)
        if (this.selectedSource === 'local') {
          Button('导入')
            .fontSize(14)
            .height(32)
            .backgroundColor(Theme.primary(this.isDark))
            .onClick(() => {
              this.pickImportFiles();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 源选择
      Row({ space: 8 }) {
        ForEach(this.sources, (source: Source) => {
          Text(source.name)
            .fontSize(13)
            .fontColor(this.selectedSource === source.key ? '#FFFFFF' : Theme.text(this.isDark))
            .backgroundColor(this.selectedSource === source.key ? Theme.primary(this.isDark) : Theme.chip(this.isDark))
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

      // 搜索栏
      if (this.selectedSource !== 'local') {
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索漫画…' })
            .layoutWeight(1)
            .height(38)
            .backgroundColor(Theme.card(this.isDark))
            .onChange((value: string) => {
              this.query = value;
            })
          Button('搜索')
            .fontSize(14)
            .height(38)
            .backgroundColor(Theme.primary(this.isDark))
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
            .color(Theme.primary(this.isDark))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.results.length === 0) {
        Column() {
          Text(this.selectedSource === 'local' ? '暂无本地漫画，点击右上角「导入」' : '没有找到漫画')
            .fontSize(14)
            .fontColor(Theme.sub(this.isDark))
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
        .layoutWeight(1)

        if (this.hasNextPage) {
          Button(this.loadingMore ? '加载中…' : '加载更多')
            .fontSize(14)
            .height(36)
            .backgroundColor(Theme.chip(this.isDark))
            .fontColor(Theme.text(this.isDark))
            .margin(12)
            .onClick(() => {
              this.loadMore();
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg(this.isDark))
  }
}
