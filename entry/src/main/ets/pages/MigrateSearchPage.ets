import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { Source, SourceRegistry } from '../source/Source';
import { JsvmSource, RawFilter } from '../source/JsvmSource';
import { ContentType, MangaRecord, SManga, WorksPage } from '../model/Models';
import { MigrateSearchParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { LoadingState } from './components/LoadingState';
import { MangaRow } from './components/MangaRow';
import { ConfirmDialog } from './components/Dialogs';
import { AppIcon } from './components/AppIcon';
import { SheetPreset } from './components/SheetPreset';
import { SourceFilterSheet } from './components/SourceFilterSheet';

// 迁移搜索页：依次处理待迁移漫画——选目标源 → 搜索 → 选取匹配项完成迁移
// 目标源支持插件过滤器（getFilterList + applyFilterState）时提供过滤入口（对齐单源浏览页）
@Component
export struct MigrateSearchPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State queue: MangaRecord[] = [];
  @State idx: number = 0;
  @State targetKey: string = '';
  @State query: string = '';
  @State results: MangaRecord[] = [];
  @State searching: boolean = false;
  @State busy: boolean = false;
  @State loading: boolean = true;
  // 目标源插件自定义过滤器（select/checkbox/tristate/text/sort/group）
  @State filters: RawFilter[] = [];
  @State showFilterSheet: boolean = false;
  // 过滤器已应用（插件侧生效，随搜索请求起效）
  @State filterSearch: boolean = false;

  originKey(): string {
    return this.queue.length > 0 ? this.queue[0].sourceKey : '';
  }

  current(): MangaRecord | undefined {
    return this.idx < this.queue.length ? this.queue[this.idx] : undefined;
  }

  // 可选目标源：与当前作品同类型，排除来源源与本地源
  targetSources(): Source[] {
    const cur = this.current();
    const type = cur !== undefined ? ContentType.normalize(cur.contentType) : ContentType.MANGA;
    const list: Source[] = [];
    for (const s of SourceRegistry.all()) {
      if (s.key !== this.originKey() && !ContentType.isLocal(s.key) && s.contentType === type) {
        list.push(s);
      }
    }
    return list;
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
      const result: WorksPage = await source.getSearchWorks(1, this.query.trim());
      this.results = await this.toRecords(source, result.works);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_search_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
    this.searching = false;
  }

  async migrate(record: MangaRecord): Promise<void> {
    const cur = this.current();
    const target = SourceRegistry.get(this.targetKey);
    if (cur === undefined || target === undefined || this.busy) {
      return;
    }
    this.busy = true;
    try {
      const detail = await target.getWorkDetail(record.url);
      await MangaRepo.migrate(cur.id, target.key, record.url, detail, target.contentType);
      Util.toastRes(this.getUIContext(), $r('app.string.migrate_item_done'), [cur.title]);
      this.advance();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.migrate_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
    this.busy = false;
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
        .padding({
          left: 16,
          right: 16,
          top: this.statusBarH + 10,
          bottom: 8
        })

        if (this.loading) {
          LoadingState()
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
          .padding({
            left: 16,
            right: 16,
            top: 4,
            bottom: 8
          })

          // 目标源
          Text($r('app.string.migrate_target_source'))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 4 })
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.targetSources(), (s: Source) => {
                Text(Util.localSourceName(this.getUIContext(), s.key, s.name))
                  .fontSize(13)
                  .fontColor(this.targetKey === s.key ? this.pal.onPrimary : this.pal.text)
                  .backgroundColor(this.targetKey === s.key ? this.pal.primary : this.pal.chip)
                  .borderRadius(14)
                  .padding({
                    left: 14,
                    right: 14,
                    top: 6,
                    bottom: 6
                  })
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
              .fontSize(15)
              .fontColor(this.pal.text)
              .placeholderColor(this.pal.sub)
              .caretColor(this.pal.primary)
              .backgroundColor(this.pal.chip)
              .borderRadius(19)
              .padding({ left: 16, right: 16 })
              .enterKeyType(EnterKeyType.Search)
              .onChange((value: string) => {
                this.query = value;
              })
              .onSubmit(() => {
                this.searchNow();
              })
            // 目标源插件过滤器入口（过滤已应用时高亮；Mihon leadingIcon: FilterList）
            if (this.targetSupportsFilters()) {
              AppIcon({
                name: 'filter_list',
                iconSize: 20,
                tint: this.filterSearch ? this.pal.primary : this.pal.sub,
              })
                .width(38)
                .height(38)
                .borderRadius(19)
                .backgroundColor(this.filterSearch ? this.pal.chip : Color.Transparent)
                .onClick(() => {
                  this.openFilterSheet();
                })
            }
            Button($r('app.string.common_search'))
              .fontSize(14)
              .height(38)
              .backgroundColor(this.pal.primary)
              .fontColor(this.pal.onPrimary)
              .enabled(this.targetKey !== '')
              .onClick(() => {
                this.searchNow();
              })
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 8,
            bottom: 8
          })

          // 搜索结果
          if (this.searching) {
            LoadingState({ spinnerSize: 28 })
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
            .scrollBar(BarState.Auto)
            .align(Alignment.Top)
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
      // 插件自定义过滤器半模态（与单源浏览页共用共享面板）：
      // 高度自适应内容（SheetPreset 默认 FIT_CONTENT），筛选项少时弹层收起，多时滚动
      .bindSheet($$this.showFilterSheet, this.filterSheetBuilder(),
        SheetPreset.fit(this.windowW, {
          title: $r('app.string.action_filter'),
          showClose: true
        }))
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

  private async loadQueue(mangaIds: number[]): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
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

  private pickTarget(key: string): void {
    if (this.targetKey === key) {
      return;
    }
    this.targetKey = key;
    this.results = [];
    // 切换目标源：清空本地过滤面板状态（过滤器在插件侧按源各自生效）
    this.filters = [];
    this.filterSearch = false;
    const cur = this.current();
    if (cur !== undefined && this.query.trim() === '') {
      this.query = cur.title;
    }
    this.searchNow();
  }

  // 插件自定义过滤器半模态（与单源浏览页共用 SourceFilterSheet）
  @Builder
  filterSheetBuilder() {
    SourceFilterSheet({
      filters: this.filters,
      onApply: (): void => {
        this.applyFilters();
      },
      onReset: (): void => {
        this.resetFilterSheet();
      },
    })
  }

  // 目标源是否支持自定义过滤器（插件导出 getFilterList + applyFilterState）
  private targetSupportsFilters(): boolean {
    const source = SourceRegistry.get(this.targetKey);
    return source instanceof JsvmSource &&
      source.hasMethod('getFilterList') && source.hasMethod('applyFilterState');
  }

  // 打开过滤器面板：拉取目标源插件当前过滤器（state 反映插件侧偏好持久值）
  private async openFilterSheet(): Promise<void> {
    const source = SourceRegistry.get(this.targetKey);
    if (!(source instanceof JsvmSource)) {
      return;
    }
    try {
      this.filters = await source.getFilterList();
    } catch (_e) {
      this.filters = [];
    }
    this.showFilterSheet = true;
  }

  // 应用过滤器并重新搜索（过滤器在插件侧生效，与关键词叠加）
  private async applyFilters(): Promise<void> {
    const source = SourceRegistry.get(this.targetKey);
    if (!(source instanceof JsvmSource)) {
      return;
    }
    // applyFilterState 契约：顶层序号由宿主回传前写入
    for (let i = 0; i < this.filters.length; i++) {
      this.filters[i].index = i;
    }
    this.showFilterSheet = false;
    await source.applyFilterState(this.filters).catch((_e: Error): void => {
    });
    this.filterSearch = true;
    await this.searchNow();
  }

  // 重置目标源插件过滤器并刷新面板
  private async resetFilterSheet(): Promise<void> {
    const source = SourceRegistry.get(this.targetKey);
    if (!(source instanceof JsvmSource)) {
      return;
    }
    try {
      await source.resetFilters();
      this.filters = await source.getFilterList();
    } catch (_e) {
      // 重置失败：保留当前面板内容
    }
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
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
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
      const target = SourceRegistry.get(this.targetKey);
      if (target === undefined || target.contentType !== cur.contentType) {
        this.targetKey = '';
        return;
      }
    }
    this.searchNow();
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function MigrateSearchBuilder() {
  MigrateSearchPage()
}
