import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { SourceRegistry, Source } from '../source/Source';
import { MangaRecord } from '../model/Models';
import { MigrateMangaParams, MigrateSearchParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { EmptyScreen } from './components/EmptyScreen';
import { SmartImage } from './components/SmartImage';

// 迁移漫画选择页（迁移 Tab 点进某个源）：勾选该书架中的漫画发起迁移
@Component
export struct MigrateMangaPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State sourceKey: string = '';
  @State items: MangaRecord[] = [];
  @State selectedIds: number[] = [];
  @State loading: boolean = true;
  private hasShown: boolean = false;

  sourceName(): string {
    const source: Source | undefined = SourceRegistry.get(this.sourceKey);
    return source !== undefined ? source.name : this.sourceKey;
  }

  private async load(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const items = await MangaRepo.getLibraryBySource(this.sourceKey);
      this.items = items;
      const valid: number[] = [];
      for (const id of this.selectedIds) {
        for (const m of items) {
          if (m.id === id && valid.indexOf(id) < 0) {
            valid.push(id);
          }
        }
      }
      this.selectedIds = valid;
    } catch (_e) {
      this.items = [];
    }
    this.loading = false;
  }

  isSelected(id: number): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggle(id: number): void {
    const next: number[] = [];
    let removed = false;
    for (const sid of this.selectedIds) {
      if (sid === id) {
        removed = true;
      } else {
        next.push(sid);
      }
    }
    if (!removed) {
      next.push(id);
    }
    this.selectedIds = next;
  }

  private allSelected(): boolean {
    return this.items.length > 0 && this.selectedIds.length === this.items.length;
  }

  private toggleAll(): void {
    if (this.allSelected()) {
      this.selectedIds = [];
      return;
    }
    const all: number[] = [];
    for (const m of this.items) {
      all.push(m.id);
    }
    this.selectedIds = all;
  }

  private startMigrate(): void {
    if (this.selectedIds.length === 0) {
      return;
    }
    const params: MigrateSearchParams = { mangaIds: this.selectedIds.slice() };
    this.pathStack.pushPathByName('MigrateSearch', params);
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
          Text(this.sourceName())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .margin({ left: 8 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.allSelected() ? $r('app.string.migrate_deselect_all') : $r('app.string.migrate_select_all'))
            .fontSize(13)
            .fontColor(this.pal.primary)
            .padding({ left: 8, right: 4 })
            .onClick(() => {
              this.toggleAll();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.statusBarH + 10, bottom: 8 })

        // 列表
        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.pal.primary)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.items.length === 0) {
          Column() {
            EmptyScreen({ message: $r('app.string.migrate_empty_library') })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              ForEach(this.items, (m: MangaRecord) => {
                Row() {
                  Toggle({ type: ToggleType.Checkbox, isOn: this.isSelected(m.id) })
                    .onChange((on: boolean) => {
                      if (on !== this.isSelected(m.id)) {
                        this.toggle(m.id);
                      }
                    })
                  if (m.thumbnailUrl === '') {
                    Column() {
                      Text('📖')
                        .fontSize(18)
                    }
                    .width(44)
                    .height(62)
                    .borderRadius(6)
                    .backgroundColor(this.pal.chip)
                    .justifyContent(FlexAlign.Center)
                    .margin({ left: 12 })
                  } else {
                    SmartImage({ url: m.thumbnailUrl, sourceKey: m.sourceKey, fit: ImageFit.Cover, fill: true })
                      .width(44)
                      .height(62)
                      .borderRadius(6)
                      .clip(true)
                      .backgroundColor(this.pal.chip)
                      .margin({ left: 12 })
                  }
                  Text(m.title)
                    .fontSize(14)
                    .fontColor(this.pal.text)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                    .margin({ left: 12 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ top: 6, bottom: 6 })
                .onClick(() => {
                  this.toggle(m.id);
                })
              }, (m: MangaRecord) => `mm-${m.id}-${this.isSelected(m.id)}`)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
        }

        // 底部迁移按钮
        Row() {
          Button($r('app.string.migrate_action', this.selectedIds.length))
            .fontSize(15)
            .width('100%')
            .backgroundColor(this.selectedIds.length > 0 ? this.pal.primary : this.pal.chip)
            .fontColor(this.selectedIds.length > 0 ? Color.White : this.pal.sub)
            .enabled(this.selectedIds.length > 0)
            .onClick(() => {
              this.startMigrate();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: this.navBarH + 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as MigrateMangaParams;
      this.sourceKey = params !== undefined && params !== null ? params.sourceKey : '';
      this.load();
    })
    .onShown(() => {
      if (this.hasShown) {
        this.load();
      }
      this.hasShown = true;
    })
  }
}
