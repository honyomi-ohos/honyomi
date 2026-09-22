import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { SourceRegistry, Source } from '../source/Source';
import { MangaRecord, SManga, MangasPage } from '../model/Models';
import { MigrateSearchParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { MangaRow } from './components/MangaRow';
import { ConfirmDialog } from './components/Dialogs';

// 迁移搜索页：依次处理待迁移漫画——选目标源 → 搜索 → 选取匹配项完成迁移
@Component
export struct MigrateSearchPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State queue: MangaRecord[] = [];
  @State idx: number = 0;
  @State targetKey: string = '';
  @State query: string = '';
  @State results: MangaRecord[] = [];
  @State searching: boolean = false;
  @State busy: boolean = false;
  @State loading: boolean = true;

  originKey(): string {
    return this.queue.length > 0 ? this.queue[0].sourceKey : '';
  }

  current(): MangaRecord | undefined {
    return this.idx < this.queue.length ? this.queue[this.idx] : undefined;
  }

  // 可选目标源：排除来源源与本地源
  targetSources(): Source[] {
    const list: Source[] = [];
    for (const s of SourceRegistry.all()) {
      if (s.key !== this.originKey() && s.key !== 'local') {
        list.push(s);
      }
    }
    return list;
  }

  private async loadQueue(mangaIds: number[]): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const queue: MangaRecord[] = [];
      for (const id of mangaIds) {
        const m = await MangaRepo.get(id);
        if (m !== undefined && m.inLibrary) {
          queue.push(m);
        }
      }
      this.queue = queue;
      const cur = this.current();
      if (cur !== undefined) {
        this.query = cur.title;
      }
    } catch (_e) {
      this.queue = [];
    }
    this.loading = false;
  }

  async toRecords(source: Source, mangas: SManga[]): Promise<MangaRecord[]> {
    const records: MangaRecord[] = [];
    for (const m of mangas) {
      const record = new MangaRecord();
      record.sourceKey = source.key;
      record.url = m.key;
      record.title = m.title;
      record.thumbnailUrl = m.coverUrl;
      record.author = m.author;
      records.push(record);
    }
    return records;
  }

  async searchNow(): Promise<void> {
    const source = SourceRegistry.get(this.targetKey);
    if (source === undefined || this.busy) {
      return;
    }
    this.searching = true;
    this.results = [];
    try {
      const result: MangasPage = await source.getSearchManga(1, this.query.trim());
      this.results = await this.toRecords(source, result.mangas);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_search_failed'), [(e as Error).message]);
    }
    this.searching = false;
  }

  private pickTarget(key: string): void {
    if (this.targetKey === key) {
      return;
    }
    this.targetKey = key;
    this.results = [];
    const cur = this.current();
    if (cur !== undefined && this.query.trim() === '') {
      this.query = cur.title;
    }
    this.searchNow();
  }

  private showConfirm(record: MangaRecord): void {
    const dialog = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.migrate_confirm_title'),
        message: record.title,
        confirmText: $r('app.string.migrate_action', 1),
        onConfirm: (): void => {
          this.migrate(record);
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  async migrate(record: MangaRecord): Promise<void> {
    const cur = this.current();
    const target = SourceRegistry.get(this.targetKey);
    if (cur === undefined || target === undefined || this.busy) {
      return;
    }
    this.busy = true;
    try {
      const detail = await target.getMangaDetail(record.url);
      await MangaRepo.migrate(cur.id, target.key, record.url, detail);
      Util.toastRes(this.getUIContext(), $r('app.string.migrate_item_done'), [cur.title]);
      this.advance();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.migrate_failed'), [(e as Error).message]);
    }
    this.busy = false;
  }

  private skip(): void {
    if (this.busy) {
      return;
    }
    this.advance();
  }

  private advance(): void {
    const next = this.idx + 1;
    if (next >= this.queue.length) {
      Util.toastRes(this.getUIContext(), $r('app.string.migrate_done'));
      this.pathStack.pop();
      return;
    }
    this.idx = next;
    this.results = [];
    const cur = this.current();
    if (cur !== undefined) {
      this.query = cur.title;
    }
    this.searchNow();
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row() {
          Text('‹')
            .fontSize(30)
            .fontColor(this.pal.text)
            .onClick(() => {
              this.pathStack.pop();
            })
          Text($r('app.string.migrate_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .margin({ left: 8 })
            .layoutWeight(1)
          Text($r('app.string.migrate_skip'))
            .fontSize(13)
            .fontColor(this.pal.primary)
            .padding({ left: 8, right: 4 })
            .onClick(() => {
              this.skip();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.statusBarH + 10, bottom: 8 })

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.pal.primary)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.queue.length === 0 || this.targetSources().length === 0) {
          Column() {
            EmptyScreen({ message: $r('app.string.migrate_no_target') })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 当前待迁移漫画
          Column() {
            Text($r('app.string.migrate_progress', this.idx + 1, this.queue.length))
              .fontSize(11)
              .fontColor(this.pal.sub)
              .width('100%')
            Text(this.current() !== undefined ? (this.current() as MangaRecord).title : '')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.text)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 4, bottom: 8 })

          // 目标源
          Text($r('app.string.migrate_target_source'))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 4 })
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.targetSources(), (s: Source) => {
                Text(s.name)
                  .fontSize(13)
                  .fontColor(this.targetKey === s.key ? '#FFFFFF' : this.pal.text)
                  .backgroundColor(this.targetKey === s.key ? this.pal.primary : this.pal.chip)
                  .borderRadius(14)
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .onClick(() => {
                    this.pickTarget(s.key);
                  })
              }, (s: Source) => `mt-${s.key}`)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .constraintSize({ maxHeight: 44 })

          // 搜索栏
          Row({ space: 8 }) {
            TextInput({ text: this.query, placeholder: $r('app.string.migrate_search_hint') })
              .layoutWeight(1)
              .height(38)
              .backgroundColor(this.pal.card)
              .enterKeyType(EnterKeyType.Search)
              .onChange((value: string) => {
                this.query = value;
              })
              .onSubmit(() => {
                this.searchNow();
              })
            Button($r('app.string.common_search'))
              .fontSize(14)
              .height(38)
              .backgroundColor(this.pal.primary)
              .enabled(this.targetKey !== '')
              .onClick(() => {
                this.searchNow();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          // 搜索结果
          if (this.searching) {
            Column() {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(this.pal.primary)
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.results.length === 0) {
            Column() {
              EmptyScreen({ message: $r('app.string.browse_no_results') })
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column() {
                ForEach(this.results, (record: MangaRecord) => {
                  MangaRow({
                    record: record,
                    subtitle: record.author,
                    onRowClick: (r: MangaRecord): void => {
                      this.showConfirm(r);
                    },
                  })
                }, (record: MangaRecord) => `ms-${record.sourceKey}-${record.url}`)
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: this.navBarH + 24 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .align(Alignment.TopStart)
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as MigrateSearchParams;
      const ids: number[] = params !== undefined && params !== null ? params.mangaIds : [];
      this.loadQueue(ids);
    })
  }
}
