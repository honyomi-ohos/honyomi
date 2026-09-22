import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { PluginService } from '../data/PluginService';
import { SourceRegistry, Source } from '../source/Source';
import { BrowseSourceParams, MigrateMangaParams, ExtensionDetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { EmptyScreen } from './components/EmptyScreen';
import { ExtensionListPanel } from './components/ExtensionListPanel';
import { InputDialog } from './components/Dialogs';
import { AppIcon } from './components/AppIcon';

// 语言显示名（对齐 Mihon 源列表的语言分组头）
const LANG_NAMES: Record<string, string> = {
  'en': 'English',
  'ja': '日本語',
  'zh': '中文',
  'zh-Hans': '中文',
  'zh-Hant': '中文（繁）',
  'ko': '한국어',
  'multi': 'Multi',
  'all': 'Multi',
};

function langDisplayName(lang: string): string {
  const name: string | undefined = LANG_NAMES[lang];
  return name !== undefined ? name : lang.toUpperCase();
}

// 源列表分节模型
export class SourceSection {
  key: string = '';
  title: Resource | string = '';
  sources: Source[] = [];

  static of(key: string, title: Resource | string, sources: Source[]): SourceSection {
    const s = new SourceSection();
    s.key = key;
    s.title = title;
    s.sources = sources;
    return s;
  }
}

// 迁移源计数模型
export class MigrateSourceCount {
  key: string = '';
  name: string = '';
  lang: string = '';
  count: number = 0;

  static of(key: string, name: string, lang: string, count: number): MigrateSourceCount {
    const m = new MigrateSourceCount();
    m.key = key;
    m.name = name;
    m.lang = lang;
    m.count = count;
    return m;
  }
}

// 源长按选项弹窗（置顶）
@CustomDialog
struct SourceOptionsDialog {
  controller?: CustomDialogController;
  sourceName: Resource | string = '';
  isPinned: boolean = false;
  onPin: () => void = () => {};
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    Column() {
      Text(this.sourceName)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ bottom: 8 })
      Text(this.isPinned ? $r('app.string.browse_unpin') : $r('app.string.browse_pin'))
        .fontSize(15)
        .fontColor(this.pal.text)
        .width('100%')
        .padding({ top: 14, bottom: 14 })
        .onClick(() => {
          if (this.controller !== undefined) {
            this.controller.close();
          }
          this.onPin();
        })
    }
    .padding(20)
    .backgroundColor(this.pal.card)
    .borderRadius(16)
    .width('80%')
  }
}

// 源语言过滤弹窗
@CustomDialog
struct LangFilterDialog {
  controller?: CustomDialogController;
  langs: string[] = [];
  initialSelected: string[] = [];
  onApply: (langs: string[]) => void = (_l: string[]) => {};
  @State checked: string[] = [];
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  aboutToAppear(): void {
    this.checked = this.initialSelected.length > 0 ? this.initialSelected.slice() : this.langs.slice();
  }

  private toggle(lang: string): void {
    const next: string[] = [];
    let removed = false;
    for (const l of this.checked) {
      if (l === lang) {
        removed = true;
      } else {
        next.push(l);
      }
    }
    if (!removed) {
      next.push(lang);
    }
    this.checked = next;
  }

  build() {
    Column() {
      Text($r('app.string.browse_filter_langs'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .width('100%')
        .margin({ bottom: 8 })

      Scroll() {
        Column() {
          ForEach(this.langs, (lang: string) => {
            Row() {
              Text(langDisplayName(lang))
                .fontSize(14)
                .fontColor(this.pal.text)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Checkbox, isOn: this.checked.indexOf(lang) >= 0 })
                .onChange((on: boolean) => {
                  if (on !== (this.checked.indexOf(lang) >= 0)) {
                    this.toggle(lang);
                  }
                })
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.toggle(lang);
            })
          }, (lang: string) => `lf-${lang}`)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 260 })
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        Button($r('app.string.browse_filter_all'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.checked = this.langs.slice();
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onApply(this.checked.slice());
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .padding(20)
    .backgroundColor(this.pal.card)
    .borderRadius(16)
    .width('80%')
  }
}

// 浏览页：图源 / 插件 / 迁移 三 Tab（对齐原版 Mihon BrowseTab）
@Component
export struct BrowsePage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('pluginsDirty') @Watch('onPluginsChanged') pluginsDirty: number = 0;
  @State currentTab: number = 0;
  // 图源 Tab
  @State sources: Source[] = [];
  @State pinnedKeys: string[] = [];
  @State enabledLangs: string[] = []; // 空数组 = 全部语言
  // 插件 Tab
  @State extSearchOpen: boolean = false;
  @State extQuery: string = '';
  // 迁移 Tab
  @State migrateItems: MigrateSourceCount[] = [];
  @State migrateLoaded: boolean = false;
  @State migrateSortByCount: boolean = true;
  @State migrateSortAsc: boolean = true;

  aboutToAppear(): void {
    this.refreshSources();
    this.loadPins();
  }

  // 插件安装/启停后刷新源列表
  onPluginsChanged(): void {
    this.refreshSources();
  }

  private refreshSources(): void {
    this.sources = SourceRegistry.all();
  }

  private loadPins(): void {
    let keys: string[] = [];
    try {
      const parsed = JSON.parse(Settings.getPinnedSources()) as string[];
      if (parsed !== null && parsed !== undefined) {
        keys = parsed;
      }
    } catch (_e) {
      keys = [];
    }
    this.pinnedKeys = keys;
  }

  private savePins(): void {
    Settings.setPinnedSources(JSON.stringify(this.pinnedKeys));
  }

  private isPinned(key: string): boolean {
    return this.pinnedKeys.indexOf(key) >= 0;
  }

  private togglePin(key: string): void {
    const next: string[] = [];
    let removed = false;
    for (const k of this.pinnedKeys) {
      if (k === key) {
        removed = true;
      } else {
        next.push(k);
      }
    }
    if (!removed) {
      next.push(key);
    }
    this.pinnedKeys = next;
    this.savePins();
  }

  private allLangs(): string[] {
    const langs: string[] = [];
    for (const s of this.sources) {
      if (langs.indexOf(s.lang) < 0) {
        langs.push(s.lang);
      }
    }
    return langs;
  }

  private sourceDisplayName(s: Source): Resource | string {
    return s.key === 'local' ? $r('app.string.browse_local_source_name') : s.name;
  }

  // 源列表分节：已置顶在前，其后按语言分组
  sourceSections(): SourceSection[] {
    const sections: SourceSection[] = [];
    const pinned: Source[] = [];
    const byLang: Record<string, Source[]> = {};
    const langOrder: string[] = [];
    for (const s of this.sources) {
      if (this.enabledLangs.length > 0 && this.enabledLangs.indexOf(s.lang) < 0) {
        continue;
      }
      if (this.isPinned(s.key)) {
        pinned.push(s);
        continue;
      }
      const group: Source[] | undefined = byLang[s.lang];
      if (group !== undefined) {
        group.push(s);
      } else {
        byLang[s.lang] = [s];
        langOrder.push(s.lang);
      }
    }
    if (pinned.length > 0) {
      sections.push(SourceSection.of('pinned', $r('app.string.browse_pinned'), pinned));
    }
    for (const lang of langOrder) {
      const group: Source[] | undefined = byLang[lang];
      if (group !== undefined && group.length > 0) {
        sections.push(SourceSection.of(`lang-${lang}`, langDisplayName(lang), group));
      }
    }
    return sections;
  }

  private showSourceOptions(s: Source): void {
    const dialog = new CustomDialogController({
      builder: SourceOptionsDialog({
        sourceName: this.sourceDisplayName(s),
        isPinned: this.isPinned(s.key),
        onPin: (): void => {
          this.togglePin(s.key);
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private showLangFilter(): void {
    const dialog = new CustomDialogController({
      builder: LangFilterDialog({
        langs: this.allLangs(),
        initialSelected: this.enabledLangs,
        onApply: (langs: string[]): void => {
          this.enabledLangs = langs.length === this.allLangs().length ? [] : langs;
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private openBrowseSource(s: Source, mode: string): void {
    const params: BrowseSourceParams = { sourceKey: s.key, mode: mode };
    this.pathStack.pushPathByName('BrowseSource', params);
  }

  // ---- 插件 Tab 菜单 ----

  private showRepoUrlDialog(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.plugin_repo_url_title'),
        placeholder: $r('app.string.plugin_repo_url_hint'),
        onConfirm: (text: string): void => {
          Settings.setPluginRepoUrl(text.trim());
          AppStorage.setOrCreate('extRepoRefresh', (AppStorage.get<number>('extRepoRefresh') ?? 0) + 1);
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private refreshRepo(): void {
    AppStorage.setOrCreate('extRepoRefresh', (AppStorage.get<number>('extRepoRefresh') ?? 0) + 1);
  }

  // ---- 迁移 Tab ----

  private async loadMigrate(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const counts = await MangaRepo.countBySource();
      const items: MigrateSourceCount[] = [];
      for (const s of SourceRegistry.all()) {
        const c: number | undefined = counts[s.key];
        if (c !== undefined && c > 0) {
          items.push(MigrateSourceCount.of(s.key,
            s.key === 'local' ? 'Local' : s.name, s.lang, c));
        }
      }
      this.migrateItems = this.sortMigrate(items);
    } catch (_e) {
      this.migrateItems = [];
    }
    this.migrateLoaded = true;
  }

  private sortMigrate(items: MigrateSourceCount[]): MigrateSourceCount[] {
    const list = items.slice();
    list.sort((a: MigrateSourceCount, b: MigrateSourceCount): number => {
      const byCount: number = a.count - b.count;
      const byName: number = a.name.localeCompare(b.name);
      const result = this.migrateSortByCount ? byCount : byName;
      return this.migrateSortAsc ? result : -result;
    });
    return list;
  }

  private openMigrateSource(item: MigrateSourceCount): void {
    const params: MigrateMangaParams = { sourceKey: item.key };
    this.pathStack.pushPathByName('MigrateManga', params);
  }

  // ---- UI ----

  @Builder
  tabLabel(title: ResourceStr, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? this.pal.primary : this.pal.text)
    }
    .height(44)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  extMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.ext_install_local') })
        .onClick(() => {
          AppStorage.setOrCreate('extLocalInstall', (AppStorage.get<number>('extLocalInstall') ?? 0) + 1);
        })
      MenuItem({ content: $r('app.string.ext_repo_settings') })
        .onClick(() => {
          this.showRepoUrlDialog();
        })
      MenuItem({ content: $r('app.string.ext_refresh_repo') })
        .onClick(() => {
          this.refreshRepo();
        })
    }
  }

  @Builder
  sourceRow(s: Source) {
    Row() {
      Text(s.name.substring(0, 1).toUpperCase())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.pal.primary)

      Column() {
        Text(this.sourceDisplayName(s))
          .fontSize(15)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(langDisplayName(s.lang))
          .fontSize(11)
          .fontColor(this.pal.sub)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      if (s.supportsLatest) {
        Text($r('app.string.browse_latest'))
          .fontSize(13)
          .fontColor(this.pal.primary)
          .padding({ left: 8, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            this.openBrowseSource(s, 'latest');
          })
      }
      AppIcon({
        name: this.isPinned(s.key) ? 'push_pin_filled' : 'push_pin',
        iconSize: 20,
        tint: this.isPinned(s.key) ? this.pal.primary : this.pal.sub,
      })
        .padding({ left: 4, right: 4 })
        .onClick(() => {
          this.togglePin(s.key);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.openBrowseSource(s, 'popular');
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.showSourceOptions(s);
        })
    )
  }

  @Builder
  sourcesTabContent() {
    if (this.sources.length === 0) {
      Column() {
        EmptyScreen({ message: $r('app.string.browse_sources_empty') })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column() {
          ForEach(this.sourceSections(), (section: SourceSection) => {
            Text(section.title)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.sub)
              .width('100%')
              .padding({ top: 12, bottom: 4 })
            ForEach(section.sources, (s: Source) => {
              this.sourceRow(s)
            }, (s: Source) => `src-${s.key}-${this.isPinned(s.key)}`)
          }, (section: SourceSection) => section.key)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .contentEndOffset(this.navBarH + 76)
    }
  }

  @Builder
  migrateTabContent() {
    if (!this.migrateLoaded) {
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(this.pal.primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.migrateItems.length === 0) {
      Column() {
        EmptyScreen({ message: $r('app.string.migrate_empty_library') })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        // 排序控制（对齐原版 MigrateSourceScreen 的 sticky header）
        Row() {
          Text($r('app.string.migrate_pick_source'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.sub)
            .layoutWeight(1)
          AppIcon({ name: this.migrateSortByCount ? 'query_stats' : 'sort', iconSize: 20, tint: this.pal.sub })
            .padding({ left: 8 })
            .onClick(() => {
              this.migrateSortByCount = !this.migrateSortByCount;
              this.migrateItems = this.sortMigrate(this.migrateItems);
            })
          AppIcon({ name: this.migrateSortAsc ? 'arrow_upward' : 'arrow_downward', iconSize: 20, tint: this.pal.sub })
            .padding({ left: 8 })
            .onClick(() => {
              this.migrateSortAsc = !this.migrateSortAsc;
              this.migrateItems = this.sortMigrate(this.migrateItems);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 4 })

        Scroll() {
          Column() {
            ForEach(this.migrateItems, (item: MigrateSourceCount) => {
              Row() {
                Text(item.name.substring(0, 1).toUpperCase())
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .textAlign(TextAlign.Center)
                  .width(40)
                  .height(40)
                  .borderRadius(20)
                  .backgroundColor(this.pal.primary)
                Column() {
                  Text(item.name)
                    .fontSize(15)
                    .fontColor(this.pal.text)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(langDisplayName(item.lang))
                    .fontSize(11)
                    .fontColor(this.pal.sub)
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 12 })
                Text(`${item.count}`)
                  .fontSize(11)
                  .fontColor('#FFFFFF')
                  .backgroundColor(this.pal.primary)
                  .borderRadius(10)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ top: 8, bottom: 8 })
              .onClick(() => {
                this.openMigrateSource(item);
              })
            }, (item: MigrateSourceCount) => `mig-${item.key}-${item.count}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
        .contentEndOffset(this.navBarH + 76)
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
    Column() {
      // 顶栏（标题 + 按页签变化的右上角按钮，对齐原版 TabbedScreen）
      Row() {
        if (this.extSearchOpen && this.currentTab === 1) {
          TextInput({ placeholder: $r('app.string.ext_search_hint') })
            .layoutWeight(1)
            .height(38)
            .backgroundColor(this.pal.card)
            .onChange((value: string) => {
              this.extQuery = value;
            })
          AppIcon({ name: 'close', iconSize: 20 })
            .padding({ left: 12, right: 4 })
            .onClick(() => {
              this.extSearchOpen = false;
              this.extQuery = '';
            })
        } else {
          Text($r('app.string.browse_title'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .layoutWeight(1)
        }

        if (this.currentTab === 0) {
          // 图源：全局搜索 + 语言过滤
          AppIcon({ name: 'travel_explore', iconSize: 22 })
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.pathStack.pushPathByName('GlobalSearch', null);
            })
          AppIcon({ name: 'filter_list', iconSize: 22 })
            .padding({ left: 0, right: 4 })
            .onClick(() => {
              this.showLangFilter();
            })
        } else if (this.currentTab === 1) {
          // 插件：搜索 + 溢出菜单
          AppIcon({ name: 'search', iconSize: 22 })
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.extSearchOpen = true;
            })
          AppIcon({ name: 'more_vert', iconSize: 22 })
            .padding({ left: 0, right: 4 })
            .bindMenu(this.extMenu)
        } else {
          // 迁移：帮助（打开迁移指南）
          AppIcon({ name: 'info', iconSize: 22 })
            .padding({ left: 12, right: 4 })
            .onClick(() => {
              const context = getContext(this) as common.UIAbilityContext;
              Util.openUrl(context, 'https://mihon.app/docs/guides/source-migration');
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })

      // 三页签 + 可滑动内容
      Tabs({ barPosition: BarPosition.Start, index: this.currentTab }) {
        TabContent() {
          this.sourcesTabContent()
        }
        .tabBar(this.tabLabel($r('app.string.browse_tab_sources'), 0))

        TabContent() {
          ExtensionListPanel({
            searchQuery: this.extQuery,
            onOpenPlugin: (pluginKey: string): void => {
              const params: ExtensionDetailParams = { pluginKey: pluginKey };
              this.pathStack.pushPathByName('ExtensionDetail', params);
            },
          })
        }
        .tabBar(this.tabLabel($r('app.string.browse_tab_extensions'), 1))

        TabContent() {
          this.migrateTabContent()
        }
        .tabBar(this.tabLabel($r('app.string.browse_tab_migrate'), 2))
      }
      .onChange((index: number) => {
        this.currentTab = index;
        if (index === 2) {
          this.loadMigrate();
        }
      })
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.bg)
  }
}
