import { picker } from '@kit.CoreFileKit';
import { SheetPreset } from './SheetPreset';
import { InstallOutcome, InstalledPlugin, PluginService, RepoEntry } from '../../data/PluginService';
import { ContentType } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { Settings } from '../../common/Settings';
import { Bp } from '../../common/Breakpoint';
import { EmptyScreen } from './EmptyScreen';
import { AppIcon } from './AppIcon';
import { TypeBadgedIcon } from './TypeBadgedIcon';
import { NsfwTag } from './NsfwTag';
import { BtTag } from './BtTag';
import { ConfirmDialog } from './Dialogs';
import { SitePreviewSheet } from './SitePreviewSheet';

// 语言显示名（与 BrowsePage / ExtensionDetailPage 保持一致的精简版）
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

// 插件信任确认弹窗（对齐 Mihon ExtensionTrustDialog）：
// 恶意插件风险告知 + 信任/卸载双动作；点遮罩关闭 = 暂不处理（保持未受信任状态）
@CustomDialog
struct TrustPluginDialog {
  controller?: CustomDialogController;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onTrust: () => void = () => {
  };
  onUninstall: () => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.ext_untrusted_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .width('100%')
      Text($r('app.string.ext_untrusted_message'))
        .fontSize(14)
        .fontColor(this.pal.sub)
        .width('100%')
      Row({ space: 12 }) {
        Button($r('app.string.common_uninstall'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor('#E05252')
          .onClick(() => {
            this.dismiss();
            this.onUninstall();
          })
        Button($r('app.string.ext_trust'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.dismiss();
            this.onTrust();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

// 在线插件语言分组（对齐 Mihon available 按语言分组）
class LangGroup {
  lang: string = '';
  label: ResourceStr = '';
  sortKey: string = '';
  entries: RepoEntry[] = [];
}

// 插件列表面板（浏览页“插件”Tab 内嵌），完全对齐 Mihon ExtensionsScreen：
// - 分组结构：待更新（含“全部更新”按钮）→ 已安装 → 在线可用（按语言分组，组内按名称排序）
// - 已安装插件有新版本时归入“待更新”分组，行尾显示更新（下载）按钮
// - 在线插件行：地球按钮预览站点（安装前查看网站交互与设计）+ 下载按钮安装；整行点击即安装
// - 已安装插件行：设置按钮进详情；整行点击进详情；长按弹卸载确认（Mihon 同款交互）
// - 下拉刷新仓库；从本地安装/仓库配置/刷新由宿主（BrowsePage 菜单）通过 AppStorage
//   计数器驱动（'extLocalInstall' / 'extRepoRefresh'）
@Component
export struct ExtensionListPanel {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  // 页签浮动条避让高度：宽屏无页签条时为 0（Index 按断点发布）
  @StorageProp('tabPadH') tabPadH: number = 76;
  @StorageProp('extRepoRefresh') @Watch('onRepoRefresh') extRepoRefresh: number = 0;
  @StorageProp('extLocalInstall') @Watch('onLocalInstall') extLocalInstall: number = 0;
  @StorageProp('pluginsDirty') @Watch('onPluginsDirty') pluginsDirty: number = 0;
  @Prop @Watch('onFilterChanged') searchQuery: string = '';
  // 内容类型过滤（宿主过滤弹窗下发）；空数组 = 全部类型
  @Prop @Watch('onFilterChanged') typeFilter: string[] = [];
  // NSFW 显示开关：关闭时隐藏仓库与已安装列表中的 NSFW 插件
  @StorageProp('showNsfw') @Watch('onFilterChanged') showNsfw: boolean = false;
  @State installed: InstalledPlugin[] = [];
  @State repoEntries: RepoEntry[] = [];
  // 已安装且有新版本（对齐 Mihon hasUpdate，归入“待更新”分组）
  @State pendingUpdates: InstalledPlugin[] = [];
  // 已安装且无新版本
  @State shownInstalled: InstalledPlugin[] = [];
  // 在线可用插件按语言分组
  @State availableGroups: LangGroup[] = [];
  // 多仓库地址列表（对齐 Mihon 多 ExtensionStore 聚合）
  @State repoUrls: string[] = [];
  // 下拉刷新 spinner 状态（Refresh 双向绑定）
  @State loadingRepo: boolean = false;
  @State busy: boolean = false;
  // 安装前站点预览弹层（在线插件行地球按钮触发）
  @State showSitePreview: boolean = false;
  @State previewSiteUrl: string = '';
  @State previewName: string = '';
  @StorageProp('windowW') windowW: number = 0;
  // 仓库 key → entry 映射（更新检查/单项更新用），随 recomputeLists 重建
  private repoByKey: Map<string, RepoEntry> = new Map();
  // 仓库请求并发防抖标志（与下拉 spinner 状态分离）
  private repoFetching: boolean = false;
  // 面板销毁标志：异步续体据此跳过 toast/写状态
  private disposed: boolean = false;
  onOpenPlugin: (pluginKey: string) => void = (_k: string) => {
  };

  aboutToAppear(): void {
    this.refreshInstalled();
    this.repoUrls = this.loadStoreUrls();
    if (this.repoUrls.length > 0) {
      this.refreshRepo();
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  // 分组头（对齐 Mihon ExtensionHeader）：标题 + 可选“全部更新”按钮
  @Builder
  sectionHeader(title: ResourceStr, showUpdateAll: boolean) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (showUpdateAll) {
        Button($r('app.string.ext_update_all'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.onPrimary)
          .backgroundColor(this.pal.primary)
          .height(30)
          .padding({ left: 14, right: 14 })
          .margin({ left: 8 })
          .onClick(() => {
            this.updateAllPending();
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 14,
      bottom: 6
    })
  }

  // PC 右键菜单「卸载」：弹卸载确认（与长按一致；移动端仍走长按手势）
  @Builder
  installedRowMenu(item: InstalledPlugin) {
    Menu() {
      MenuItem({ content: $r('app.string.common_uninstall') })
        .onClick(() => {
          this.confirmUninstall(item);
        })
    }
  }

  // 整行点击进详情；长按弹卸载确认；有更新时行尾显示更新按钮
  @Builder
  installedRow(item: InstalledPlugin, updatable: boolean) {
    Row() {
      TypeBadgedIcon({
        iconPath: item.iconPath,
        fallbackChar: this.firstCharOf(item.manifest.name),
        iconSize: 40,
        cornerRadius: 10,
        contentType: item.manifest.contentType,
        badgeBorder: this.pal.bg,
      })

      Column() {
        Text(item.manifest.name)
          .fontSize(15)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(this.langLabel(item.manifest.lang))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(1)
          Text(` · ${item.manifest.version}`)
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(1)
          if (!item.trusted) {
            // 未受信任徽标（对齐 Mihon ext_untrusted 标签）
            Text($r('app.string.ext_untrusted_tag'))
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .backgroundColor('#E8A33D')
              .borderRadius(4)
              .padding({
                left: 4,
                right: 4,
                top: 1,
                bottom: 1
              })
              .margin({ left: 6 })
          }
          if (item.manifest.nsfw) {
            NsfwTag()
              .margin({ left: 6 })
          }
          if (item.manifest.bt) {
            BtTag()
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 16 })

      if (!item.trusted) {
        // 未受信任：信任确认入口（对齐 Mihon VerifiedUser 图标），设置按钮隐藏
        AppIcon({ name: 'verified_user', iconSize: 22, tint: '#E8A33D' })
          .padding({
            left: 8,
            right: 8,
            top: 10,
            bottom: 10
          })
          .onClick(() => {
            this.showTrustDialog(item.manifest.key, item.manifest.name);
          })
      } else {
        // 设置按钮进插件详情（Mihon Loaded 行同款）
        AppIcon({ name: 'settings', iconSize: 22, tint: this.pal.sub })
          .padding({
            left: 8,
            right: updatable ? 0 : 8,
            top: 10,
            bottom: 10
          })
          .onClick(() => {
            this.onOpenPlugin(item.manifest.key);
          })
      }

      // 有新版本时显示更新按钮（对齐 Mihon hasUpdate → Download 图标）
      if (updatable) {
        AppIcon({ name: 'download', iconSize: 22, tint: this.pal.primary })
          .padding({
            left: 8,
            right: 8,
            top: 10,
            bottom: 10
          })
          .onClick(() => {
            this.updateOne(item.manifest.key);
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: 8
    })
    .onClick(() => {
      // 未受信任：整行点击弹信任确认（对齐 Mihon Untrusted 行交互）；已受信任进详情
      if (item.trusted) {
        this.onOpenPlugin(item.manifest.key);
      } else {
        this.showTrustDialog(item.manifest.key, item.manifest.name);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((_e: GestureEvent) => {
          this.confirmUninstall(item);
        })
    )
    .bindContextMenu((): void => {
      this.installedRowMenu(item);
    }, ResponseType.RightClick)
  }

  // 在线可用插件行：地球按钮预览站点 + 下载按钮安装；整行点击即安装（Mihon Available 行同款）
  @Builder
  availableRow(entry: RepoEntry) {
    Row() {
      TypeBadgedIcon({
        iconPath: entry.icon,
        fallbackChar: this.firstCharOf(entry.name),
        iconSize: 40,
        cornerRadius: 10,
        contentType: entry.contentType,
        badgeBorder: this.pal.bg,
      })

      Column() {
        Text(entry.name)
          .fontSize(15)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(this.langLabel(entry.lang))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(1)
          Text(` · ${entry.version}`)
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(1)
          if (entry.nsfw) {
            NsfwTag()
              .margin({ left: 6 })
          }
          if (entry.bt) {
            BtTag()
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 16 })

      // 安装前预览插件对应网站（仓库索引声明 site 时显示）
      if (entry.site !== '') {
        AppIcon({ name: 'public', iconSize: 22, tint: this.pal.sub })
          .padding({
            left: 8,
            right: 8,
            top: 10,
            bottom: 10
          })
          .onClick(() => {
            this.previewSiteUrl = entry.site;
            this.previewName = entry.name;
            this.showSitePreview = true;
          })
      }

      AppIcon({ name: 'download', iconSize: 22, tint: this.pal.primary })
        .padding({
          left: 8,
          right: 8,
          top: 10,
          bottom: 10
        })
        .onClick(() => {
          this.installFromRepo(entry);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: 8
    })
    .onClick(() => {
      this.installFromRepo(entry);
    })
  }

  // 站点预览半模态弹层内容（SitePreviewSheet 承载，样式对齐 Mihon WebView）
  @Builder
  sitePreviewBuilder() {
    SitePreviewSheet({
      siteUrl: this.previewSiteUrl,
      defaultTitle: this.previewName,
      onClose: (): void => {
        this.showSitePreview = false;
      },
    })
  }

  build() {
    Refresh({ refreshing: $$this.loadingRepo }) {
      Scroll() {
        Column() {
          // 待更新分组（对齐 Mihon ext_updates_pending，含“全部更新”按钮）
          if (this.pendingUpdates.length > 0) {
            this.sectionHeader($r('app.string.ext_updates_pending'), true)
            ForEach(this.pendingUpdates, (item: InstalledPlugin) => {
              this.installedRow(item, true)
            }, (item: InstalledPlugin) => `plug-${item.manifest.key}-${item.manifest.versionCode}-${item.iconPath}-${item.trusted}`)
          }

          // 已安装分组（无新版本）
          if (this.shownInstalled.length > 0) {
            this.sectionHeader($r('app.string.plugin_installed_section'), false)
            ForEach(this.shownInstalled, (item: InstalledPlugin) => {
              this.installedRow(item, false)
            }, (item: InstalledPlugin) => `plug-${item.manifest.key}-${item.manifest.versionCode}-${item.iconPath}-${item.trusted}`)
          }

          if (this.repoUrls.length === 0) {
            // 未配置仓库：提示 + 已安装为空时给空态
            this.sectionHeader($r('app.string.plugin_repo'), false)
            if (this.pendingUpdates.length === 0 && this.shownInstalled.length === 0) {
              EmptyScreen({
                message: $r('app.string.plugin_repo_hint'),
                compact: true,
              })
            } else {
              Text($r('app.string.plugin_repo_hint'))
                .fontSize(12)
                .fontColor(this.pal.sub)
                .width('100%')
                .padding({
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 8
                })
            }
          } else if (this.loadingRepo && this.repoEntries.length === 0) {
            // 首次加载仓库
            this.sectionHeader($r('app.string.plugin_repo'), false)
            Row({ space: 8 }) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(this.pal.primary)
              Text($r('app.string.plugin_repo_loading'))
                .fontSize(12)
                .fontColor(this.pal.sub)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 16, bottom: 16 })
          } else if (this.availableGroups.length === 0) {
            // 仓库无匹配：全部为空时空态，否则静默（有已安装内容即可）
            if (this.pendingUpdates.length === 0 && this.shownInstalled.length === 0) {
              EmptyScreen({
                message: this.hasActiveFilter() ?
                  $r('app.string.ext_search_no_match') :
                  $r('app.string.plugin_empty'),
                compact: true,
              })
            }
          } else {
            // 在线可用：按语言分组展示（对齐 Mihon available 按语言分组）
            ForEach(this.availableGroups, (g: LangGroup) => {
              this.sectionHeader(g.label, false)
              ForEach(g.entries, (entry: RepoEntry) => {
                this.availableRow(entry)
              }, (entry: RepoEntry) => `repo-${entry.key}-${entry.versionCode}-${entry.icon}`)
            }, (g: LangGroup) => `grp-${g.lang}`)
          }
        }
        .width('100%')
        // 大屏限宽缩进：滚动容器全宽（滚动条贴窗口边），内容列与浏览页 720 列对齐
        .padding({
          left: Bp.contentInset(this.windowW),
          right: Bp.contentInset(this.windowW)
        })
      }
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .contentEndOffset(this.navBarH + this.tabPadH)
      .width('100%')
      .height('100%')
    }
    .onRefreshing(() => {
      this.refreshRepo();
    })
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSitePreview, this.sitePreviewBuilder(),
      SheetPreset.fit(this.windowW, {
        height: SheetSize.LARGE,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: false,
        wideWidth: 560,
        maskColor: 'rgba(0,0,0,0.45)'
      }))
  }

  // 宿主改仓库列表（增删/刷新）后触发
  private onRepoRefresh(): void {
    this.repoUrls = this.loadStoreUrls();
    this.repoEntries = [];
    this.recomputeLists();
    if (this.repoUrls.length > 0) {
      this.refreshRepo();
    }
  }

  // 当前仓库地址列表（Settings 多仓库记录）
  private loadStoreUrls(): string[] {
    const urls: string[] = [];
    for (const store of Settings.getPluginStores()) {
      urls.push(store.url);
    }
    return urls;
  }

  // 宿主溢出菜单“从本地安装”触发
  private onLocalInstall(): void {
    this.pickPluginFile();
  }

  // 插件安装/卸载/重载后同步刷新已安装列表
  private onPluginsDirty(): void {
    this.refreshInstalled();
  }

  // 已安装列表来自 DB 元数据索引（异步），刷新后重算分组
  private async refreshInstalled(): Promise<void> {
    this.installed = await PluginService.listInstalled();
    if (this.disposed) {
      return;
    }
    this.recomputeLists();
  }

  // 宿主搜索词/类型过滤/NSFW 开关变化时重算分组
  private onFilterChanged(): void {
    this.recomputeLists();
  }

  private firstCharOf(name: string): string {
    if (name.length === 0) {
      return '?';
    }
    return name.substring(0, 1).toUpperCase();
  }

  // 分组重算（对齐 Mihon ExtensionsViewModel.items）：

  private matchesQuery(name: string, key: string): boolean {
    const q = this.searchQuery.trim().toLowerCase();
    if (q === '') {
      return true;
    }
    return name.toLowerCase().indexOf(q) >= 0 || key.toLowerCase().indexOf(q) >= 0;
  }

  // 仓库索引未声明 contentType 的条目按宿主约定视为漫画
  private effectiveType(contentType: string): string {
    return contentType === '' ? ContentType.MANGA : contentType;
  }

  private matchesType(contentType: string): boolean {
    if (this.typeFilter.length === 0) {
      return true;
    }
    return this.typeFilter.indexOf(this.effectiveType(contentType)) >= 0;
  }

  // 语言显示名（all/multi 用本地化“多语言”，对齐 Mihon multi_lang）
  private langLabel(lang: string): ResourceStr {
    if (lang === '' || lang === 'all' || lang === 'multi') {
      return $r('app.string.ext_multi_lang');
    }
    const name: string | undefined = LANG_NAMES[lang];
    return name !== undefined ? name : lang.toUpperCase();
  }

  // 语言分组排序键（纯字符串，供 localeCompare）
  private sortKeyOf(lang: string): string {
    if (lang === '' || lang === 'all' || lang === 'multi') {
      return 'Multi';
    }
    const name: string | undefined = LANG_NAMES[lang];
    return name !== undefined ? name : lang.toUpperCase();
  }

  // 待更新（已安装且仓库版本更高）→ 已安装（无更新）→ 在线可用（未安装）按语言分组
  private recomputeLists(): void {
    const byKey = new Map<string, RepoEntry>();
    for (const entry of this.repoEntries) {
      byKey.set(entry.key, entry);
    }
    this.repoByKey = byKey;

    const installedKeys = new Set<string>();
    const pending: InstalledPlugin[] = [];
    const current: InstalledPlugin[] = [];
    for (const item of this.installed) {
      installedKeys.add(item.manifest.key);
      if (item.manifest.nsfw && !this.showNsfw) {
        continue;
      }
      if (!this.matchesQuery(item.manifest.name, item.manifest.key) ||
        !this.matchesType(item.manifest.contentType)) {
        continue;
      }
      const entry: RepoEntry | undefined = byKey.get(item.manifest.key);
      if (entry !== undefined && entry.versionCode > item.manifest.versionCode) {
        pending.push(item);
      } else {
        current.push(item);
      }
    }
    this.pendingUpdates = pending;
    this.shownInstalled = current;

    // 在线可用：未安装且通过过滤，按语言分组（组内按名称排序，组间按语言显示名排序）
    const groups: LangGroup[] = [];
    for (const entry of this.repoEntries) {
      if (installedKeys.has(entry.key)) {
        continue;
      }
      if (entry.nsfw && !this.showNsfw) {
        continue;
      }
      if (!this.matchesQuery(entry.name, entry.key) || !this.matchesType(entry.contentType)) {
        continue;
      }
      let group: LangGroup | undefined = undefined;
      for (const g of groups) {
        if (g.lang === entry.lang) {
          group = g;
          break;
        }
      }
      if (group === undefined) {
        group = new LangGroup();
        group.lang = entry.lang;
        group.label = this.langLabel(entry.lang);
        group.sortKey = this.sortKeyOf(entry.lang);
        groups.push(group);
      }
      group.entries.push(entry);
    }
    const entrySorter = (a: RepoEntry, b: RepoEntry): number => a.name.localeCompare(b.name);
    const groupSorter = (a: LangGroup, b: LangGroup): number => a.sortKey.localeCompare(b.sortKey);
    for (const g of groups) {
      g.entries.sort(entrySorter);
    }
    groups.sort(groupSorter);
    this.availableGroups = groups;
  }

  // 当前是否有搜索/类型过滤（空态文案切换用）
  private hasActiveFilter(): boolean {
    return this.searchQuery.trim() !== '' || this.typeFilter.length > 0;
  }

  // 多仓库聚合拉取（对齐 Mihon findAvailableExtensions 多 store 聚合）：
  // 逐仓库拉取索引，合并去重（同 key 保留 versionCode 更高者）；单仓库失败不中断其余，
  // 全部失败才报错（部分成功按成功处理）
  private async refreshRepo(): Promise<void> {
    if (this.repoUrls.length === 0 || this.repoFetching) {
      // 无仓库时收起下拉 spinner
      if (this.repoUrls.length === 0) {
        this.loadingRepo = false;
      }
      return;
    }
    this.repoFetching = true;
    this.loadingRepo = true;
    try {
      const lists: RepoEntry[][] = [];
      let firstError = '';
      for (const url of this.repoUrls) {
        try {
          lists.push(await PluginService.fetchRepo(url));
        } catch (e) {
          if (firstError === '') {
            firstError = Util.errText(this.getUIContext(), (e as Error).message);
          }
        }
      }
      if (this.disposed) {
        return;
      }
      if (lists.length === 0 && firstError !== '') {
        Util.toastRes(this.getUIContext(), $r('app.string.plugin_repo_load_failed'), [firstError]);
      }
      this.repoEntries = PluginService.mergeRepoEntries(lists);
      this.recomputeLists();
    } finally {
      if (!this.disposed) {
        this.loadingRepo = false;
      }
      this.repoFetching = false;
    }
  }

  private async pickPluginFile(): Promise<void> {
    if (this.busy) {
      return;
    }
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.honyomiplug', '.zip'];
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: Array<string> = await docPicker.select(options);
      if (uris.length === 0) {
        return;
      }
      await this.installUri(uris[0]);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_pick_file_failed'));
    }
  }

  private async installUri(uri: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const outcome: InstallOutcome = await PluginService.installFromFile(uri);
      if (this.disposed) {
        return;
      }
      this.refreshInstalled();
      PluginService.markDirty();
      if (outcome.trusted) {
        Util.toastRes(this.getUIContext(), $r('app.string.plugin_installed'), [outcome.key]);
      } else {
        // 未受信任：弹信任确认（信任后激活 / 卸载），对齐 Mihon 安装后弹 ExtensionTrustDialog
        this.showTrustDialog(outcome.key, outcome.name);
      }
    } catch (e) {
      if (this.disposed) {
        return;
      }
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_install_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
    if (!this.disposed) {
      this.busy = false;
    }
  }

  // 单次仓库安装/更新核心（不含 busy 门控，供单项安装与“全部更新”复用）：
  // interactive = true 时未受信任结果弹信任确认；批量更新传 false（行内展示未受信任
  // 状态，由用户逐个点击确认，避免连续弹窗）
  private async performRepoInstall(entry: RepoEntry, interactive: boolean): Promise<void> {
    try {
      const outcome: InstallOutcome = await PluginService.installFromRepo(entry);
      if (this.disposed) {
        return;
      }
      this.refreshInstalled();
      PluginService.markDirty();
      if (outcome.trusted) {
        Util.toastRes(this.getUIContext(), $r('app.string.plugin_installed_name'), [entry.name]);
      } else if (interactive) {
        this.showTrustDialog(outcome.key, entry.name);
      }
    } catch (e) {
      if (this.disposed) {
        return;
      }
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_install_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
  }

  private async installFromRepo(entry: RepoEntry): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    await this.performRepoInstall(entry, true);
    if (!this.disposed) {
      this.busy = false;
    }
  }

  // 已安装插件行（待更新/已安装分组共用）：图标 + 名称 + 语言·版本(+NSFW) + 操作

  // “待更新”分组行尾更新按钮：按已安装插件 key 找仓库条目更新
  private async updateOne(key: string): Promise<void> {
    const entry: RepoEntry | undefined = this.repoByKey.get(key);
    if (entry === undefined) {
      return;
    }
    await this.installFromRepo(entry);
  }

  // Mihon ext_update_all：按快照顺序逐个更新“待更新”分组插件
  private async updateAllPending(): Promise<void> {
    if (this.busy) {
      return;
    }
    const snapshot: RepoEntry[] = [];
    for (const item of this.pendingUpdates) {
      const entry: RepoEntry | undefined = this.repoByKey.get(item.manifest.key);
      if (entry !== undefined) {
        snapshot.push(entry);
      }
    }
    if (snapshot.length === 0) {
      return;
    }
    this.busy = true;
    for (const entry of snapshot) {
      await this.performRepoInstall(entry, false);
    }
    if (!this.disposed) {
      this.busy = false;
    }
  }

  // ---- 信任确认（对齐 Mihon ExtensionTrustDialog）----

  // 未受信任插件确认弹窗：信任 → 登记信任并激活（拉引擎注册源）；卸载 → 移除插件；
  // 点遮罩/返回关闭 = 暂不处理（保持未受信任状态，不执行任何插件代码）
  private showTrustDialog(key: string, name: string): void {
    const dialog = new CustomDialogController({
      builder: TrustPluginDialog({
        onTrust: (): void => {
          dialog.close();
          this.activateTrusted(key, name);
        },
        onUninstall: (): void => {
          dialog.close();
          this.uninstallPlugin(key);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  // 用户确认信任：登记信任记录并拉起引擎激活源，完成后刷新列表
  private async activateTrusted(key: string, name: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await PluginService.trustAndActivate(key);
      if (this.disposed) {
        return;
      }
      this.refreshInstalled();
      PluginService.markDirty();
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_trust_done'), [name]);
    } catch (e) {
      if (this.disposed) {
        return;
      }
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_install_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
    if (!this.disposed) {
      this.busy = false;
    }
  }

  // 长按已安装插件 → 卸载确认（Mihon onLongClickItem 同款交互）
  private confirmUninstall(item: InstalledPlugin): void {
    const dialog = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.ext_uninstall_title'),
        message: Util.resStr(this.getUIContext(), $r('app.string.ext_uninstall_msg'),
          [item.manifest.name]),
        confirmText: $r('app.string.common_uninstall'),
        onConfirm: (): void => {
          this.uninstallPlugin(item.manifest.key);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private async uninstallPlugin(key: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await PluginService.uninstall(key);
      PluginService.markDirty();
      if (!this.disposed) {
        Util.toastRes(this.getUIContext(), $r('app.string.plugin_uninstalled'), [key]);
      }
    } catch (e) {
      if (!this.disposed) {
        Util.toastRes(this.getUIContext(), $r('app.string.plugin_uninstall_failed'));
      }
    }
    if (!this.disposed) {
      this.busy = false;
    }
  }
}
