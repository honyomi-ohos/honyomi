import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { PluginService } from '../data/PluginService';
import { SourceRegistry, Source } from '../source/Source';
import { BrowseSourceParams, MigrateMangaParams, ExtensionDetailParams } from '../model/RouteParams';
import { ContentType } from '../model/Models';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { EmptyScreen } from './components/EmptyScreen';
import { ExtensionListPanel } from './components/ExtensionListPanel';
import { InputDialog } from './components/Dialogs';
import { AppIcon } from './components/AppIcon';
import { TypeBadgedIcon } from './components/TypeBadgedIcon';
import { NsfwTag } from './components/NsfwTag';

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
  iconPath: string = '';
  contentType: string = '';

  static of(key: string, name: string, lang: string, count: number,
    iconPath: string = '', contentType: string = ''): MigrateSourceCount {
    const m = new MigrateSourceCount();
    m.key = key;
    m.name = name;
    m.lang = lang;
    m.count = count;
    m.iconPath = iconPath;
    m.contentType = contentType;
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
  onClose: () => void = () => {};
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }

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
          this.dismiss();
          this.onPin();
        })
    }
    .padding(20)
    .width('100%')
  }
}

// 内容类型过滤项（漫画/小说/动画）
const FILTER_TYPES: string[] = [ContentType.MANGA, ContentType.NOVEL, ContentType.VIDEO];

function typeDisplayName(t: string): Resource {
  if (t === ContentType.NOVEL) {
    return $r('app.string.browse_type_novel');
  }
  if (t === ContentType.VIDEO) {
    return $r('app.string.browse_type_video');
  }
  return $r('app.string.browse_type_manga');
}

// 源/插件过滤弹窗：语言（langs 非空时显示）+ 内容类型（漫画/小说/动画）
@CustomDialog
struct SourceFilterDialog {
  controller?: CustomDialogController;
  langs: string[] = [];
  initialLangs: string[] = [];
  initialTypes: string[] = [];
  onApply: (langs: string[], types: string[]) => void = (_l: string[], _t: string[]) => {};
  onClose: () => void = () => {};
  @State checkedLangs: string[] = [];
  @State checkedTypes: string[] = [];
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  aboutToAppear(): void {
    this.checkedLangs = this.initialLangs.length > 0 ? this.initialLangs.slice() : this.langs.slice();
    this.checkedTypes = this.initialTypes.length > 0 ? this.initialTypes.slice() : FILTER_TYPES.slice();
  }

  private toggleLang(lang: string): void {
    const next: string[] = [];
    let removed = false;
    for (const l of this.checkedLangs) {
      if (l === lang) {
        removed = true;
      } else {
        next.push(l);
      }
    }
    if (!removed) {
      next.push(lang);
    }
    this.checkedLangs = next;
  }

  private toggleType(t: string): void {
    const next: string[] = [];
    let removed = false;
    for (const item of this.checkedTypes) {
      if (item === t) {
        removed = true;
      } else {
        next.push(item);
      }
    }
    if (!removed) {
      next.push(t);
    }
    this.checkedTypes = next;
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }

  build() {
    Column() {
      Text($r('app.string.action_filter'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .width('100%')
        .margin({ bottom: 8 })

      Scroll() {
        Column() {
          if (this.langs.length > 0) {
            Text($r('app.string.browse_filter_langs'))
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.sub)
              .width('100%')
              .padding({ top: 8, bottom: 4 })

            ForEach(this.langs, (lang: string) => {
              Row() {
                Text(langDisplayName(lang))
                  .fontSize(14)
                  .fontColor(this.pal.text)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Checkbox, isOn: this.checkedLangs.indexOf(lang) >= 0 })
                  .hitTestBehavior(HitTestMode.None)
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.toggleLang(lang);
              })
            }, (lang: string) => `lf-${lang}`)
          }

          Text($r('app.string.lib_filter_content'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.sub)
            .width('100%')
            .padding({ top: 8, bottom: 4 })

          ForEach(FILTER_TYPES, (t: string) => {
            Row() {
              Text(typeDisplayName(t))
                .fontSize(14)
                .fontColor(this.pal.text)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Checkbox, isOn: this.checkedTypes.indexOf(t) >= 0 })
                .hitTestBehavior(HitTestMode.None)
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.toggleType(t);
            })
          }, (t: string) => `tf-${t}`)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 300 })
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        Button($r('app.string.browse_filter_all'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.checkedLangs = this.langs.slice();
            this.checkedTypes = FILTER_TYPES.slice();
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .onClick(() => {
            this.dismiss();
            this.onApply(this.checkedLangs.slice(), this.checkedTypes.slice());
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .padding(20)
    .width('100%')
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
  // NSFW 源显示开关（浏览设置页写入 AppStorage）
  @StorageProp('showNsfw') showNsfw: boolean = false;
  @State currentTab: number = 0;
  // 图源 Tab
  @State sources: Source[] = [];
  @State pinnedKeys: string[] = [];
  @State enabledLangs: string[] = []; // 空数组 = 全部语言
  @State enabledTypes: string[] = []; // 空数组 = 全部内容类型
  // 插件 Tab
  @State extSearchOpen: boolean = false;
  @State extQuery: string = '';
  @State extTypes: string[] = []; // 空数组 = 全部内容类型
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
    // slice() 强制生成新数组引用，确保 @State 检测到变化并触发重绘
    this.sources = SourceRegistry.all().slice();
  }

  private loadPins(): void {
    let keys: string[] = [];
    try {
      const parsed = JSON.parse(Settings.getPinnedSources()) as string[];
      // 存储值可能被写坏为非数组（旧版本/手改），Array.isArray 防护
      if (Array.isArray(parsed)) {
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
    if (s.key === 'local') {
      return $r('app.string.browse_local_source_name');
    }
    if (s.key === 'local_novel') {
      return $r('app.string.browse_local_novel_name');
    }
    if (s.key === 'local_video') {
      return $r('app.string.browse_local_video_name');
    }
    return s.name;
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
      if (this.enabledTypes.length > 0 && this.enabledTypes.indexOf(s.contentType) < 0) {
        continue;
      }
      // 关闭“显示 NSFW 源”时隐藏 NSFW 源
      if (s.nsfw && !this.showNsfw) {
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

  // 分节键需包含成员源 key：ForEach 按 key 复用组件，若 key 只含语言标识，
  // 运行中新增/移除源时分节被原样复用，列表不会重建（新装插件源不显示）
  private sectionKey(section: SourceSection): string {
    let fp: string = section.key;
    for (const s of section.sources) {
      fp += `|${s.key}`;
    }
    return fp;
  }

  private showSourceOptions(s: Source): void {
    const dialog = new CustomDialogController({
      builder: SourceOptionsDialog({
        sourceName: this.sourceDisplayName(s),
        isPinned: this.isPinned(s.key),
        onPin: (): void => {
          this.togglePin(s.key);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private showSourceFilter(): void {
    const dialog = new CustomDialogController({
      builder: SourceFilterDialog({
        langs: this.allLangs(),
        initialLangs: this.enabledLangs,
        initialTypes: this.enabledTypes,
        onApply: (langs: string[], types: string[]): void => {
          this.enabledLangs = langs.length === 0 || langs.length === this.allLangs().length ? [] : langs;
          this.enabledTypes = types.length === FILTER_TYPES.length ? [] : types;
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  // 插件 Tab：仅按内容类型过滤（语言沿用仓库声明，不提供过滤）
  private showExtTypeFilter(): void {
    const dialog = new CustomDialogController({
      builder: SourceFilterDialog({
        langs: [],
        initialLangs: [],
        initialTypes: this.extTypes,
        onApply: (_langs: string[], types: string[]): void => {
          this.extTypes = types.length === FILTER_TYPES.length ? [] : types;
        },
        onClose: (): void => {
          dialog.close();
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
        onClose: (): void => {
          dialog.close();
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

  // 本地源名称本地化：MigrateSourceCount.name 为 string，需在此把 Resource 解析为字符串
  private sourceNameText(s: Source): string {
    if (s.key === 'local') {
      return Util.resStr(this.getUIContext(), $r('app.string.browse_local_source_name'));
    }
    if (s.key === 'local_novel') {
      return Util.resStr(this.getUIContext(), $r('app.string.browse_local_novel_name'));
    }
    if (s.key === 'local_video') {
      return Util.resStr(this.getUIContext(), $r('app.string.browse_local_video_name'));
    }
    return s.name;
  }

  private async loadMigrate(): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const counts = await MangaRepo.countBySource();
      const items: MigrateSourceCount[] = [];
      for (const s of SourceRegistry.all()) {
        const c: number | undefined = counts[s.key];
        if (c !== undefined && c > 0) {
          items.push(MigrateSourceCount.of(s.key, this.sourceNameText(s), s.lang, c, s.iconPath, s.contentType));
        }
      }
      this.migrateItems = this.sortMigrate(items);
    } catch (_e) {
      this.migrateItems = [];
      Util.toastRes(this.getUIContext(), $r('app.string.migrate_load_failed'));
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
      TypeBadgedIcon({
        iconPath: s.iconPath,
        fallbackChar: s.name.substring(0, 1).toUpperCase(),
        iconSize: 40,
        cornerRadius: 20,
        contentType: s.contentType,
        badgeBorder: this.pal.bg,
      })

      Column() {
        Text(this.sourceDisplayName(s))
          .fontSize(15)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(langDisplayName(s.lang))
            .fontSize(11)
            .fontColor(this.pal.sub)
            .margin({ top: 2 })
          if (s.nsfw) {
            NsfwTag()
              .margin({ left: 6, top: 2 })
          }
        }
        .alignItems(VerticalAlign.Center)
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
    } else if (this.sourceSections().length === 0) {
      // 有源但被语言/类型过滤后为空
      Column() {
        EmptyScreen({ message: $r('app.string.browse_type_empty') })
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
          }, (section: SourceSection) => this.sectionKey(section))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
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
                TypeBadgedIcon({
                  iconPath: item.iconPath,
                  fallbackChar: item.name.substring(0, 1).toUpperCase(),
                  iconSize: 40,
                  cornerRadius: 20,
                  contentType: item.contentType,
                  badgeBorder: this.pal.bg,
                })
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
            }, (item: MigrateSourceCount) => `mig-${item.key}-${item.count}-${item.iconPath}-${item.contentType}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
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
          // 图源：全局搜索 + 过滤（语言/内容类型）
          AppIcon({ name: 'travel_explore', iconSize: 22 })
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.pathStack.pushPathByName('GlobalSearch', null);
            })
          AppIcon({ name: 'filter_list', iconSize: 22 })
            .padding({ left: 0, right: 4 })
            .onClick(() => {
              this.showSourceFilter();
            })
        } else if (this.currentTab === 1) {
          // 插件：搜索 + 类型过滤 + 溢出菜单
          AppIcon({ name: 'search', iconSize: 22 })
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.extSearchOpen = true;
            })
          AppIcon({ name: 'filter_list', iconSize: 22 })
            .padding({ left: 0, right: 12 })
            .onClick(() => {
              this.showExtTypeFilter();
            })
          AppIcon({ name: 'more_vert', iconSize: 22 })
            .padding({ left: 0, right: 4 })
            .bindMenu(this.extMenu)
        } else {
          // 迁移：帮助（打开迁移指南）
          AppIcon({ name: 'info', iconSize: 22 })
            .padding({ left: 12, right: 4 })
            .onClick(() => {
              const context = Util.hostAbilityContext(this.getUIContext());
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
            typeFilter: this.extTypes,
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
