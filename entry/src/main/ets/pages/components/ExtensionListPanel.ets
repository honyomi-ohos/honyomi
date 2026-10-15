import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { PluginService, InstalledPlugin, RepoEntry } from '../../data/PluginService';
import { ContentType } from '../../model/Models';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { Settings } from '../../common/Settings';
import { Bp } from '../../common/Breakpoint';
import { EmptyScreen } from './EmptyScreen';
import { AppIcon } from './AppIcon';
import { TypeBadgedIcon } from './TypeBadgedIcon';
import { NsfwTag } from './NsfwTag';
import { SitePreviewSheet } from './SitePreviewSheet';

// 插件列表面板（浏览页“插件”Tab 内嵌）：已安装 / 在线仓库
// 对齐 Mihon：整行点击进入插件详情页；从本地安装/仓库配置/刷新由宿主（BrowsePage 菜单）
// 通过 AppStorage 计数器驱动（'extLocalInstall' / 'extRepoRefresh'）
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
  onOpenPlugin: (pluginKey: string) => void = (_k: string) => {};
  @State installed: InstalledPlugin[] = [];
  @State repoEntries: RepoEntry[] = [];
  // filteredInstalled 结果缓存（build 内多处使用，避免同一 build 重复重建数组）
  @State shownInstalled: InstalledPlugin[] = [];
  @State repoUrl: string = '';
  @State loadingRepo: boolean = false;
  @State busy: boolean = false;
  // 安装前站点预览弹层（在线插件行地球按钮触发）
  @State showSitePreview: boolean = false;
  @State previewSiteUrl: string = '';
  @State previewName: string = '';
  @StorageProp('windowW') windowW: number = 0;
  // 面板销毁标志：异步续体据此跳过 toast/写状态
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.refreshInstalled();
    this.repoUrl = Settings.getPluginRepoUrl();
    if (this.repoUrl !== '') {
      this.refreshRepo();
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  // 宿主改仓库地址或手动刷新后触发
  private onRepoRefresh(): void {
    this.repoUrl = Settings.getPluginRepoUrl();
    this.repoEntries = [];
    if (this.repoUrl !== '') {
      this.refreshRepo();
    }
  }

  // 宿主溢出菜单“从本地安装”触发
  private onLocalInstall(): void {
    this.pickPluginFile();
  }

  // 插件安装/卸载/重载后同步刷新已安装列表
  private onPluginsDirty(): void {
    this.refreshInstalled();
  }

  // 已安装列表来自 DB 元数据索引（异步），刷新后重算过滤缓存
  private async refreshInstalled(): Promise<void> {
    this.installed = await PluginService.listInstalled();
    if (this.disposed) {
      return;
    }
    this.recomputeShownInstalled();
  }

  // 宿主搜索词或类型过滤变化时重算已安装过滤缓存
  private onFilterChanged(): void {
    this.recomputeShownInstalled();
  }

  private firstCharOf(name: string): string {
    if (name.length === 0) {
      return '?';
    }
    return name.substring(0, 1).toUpperCase();
  }

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

  // 已安装过滤结果缓存计算（installed/searchQuery/typeFilter/showNsfw 任一变化时调用）
  private recomputeShownInstalled(): void {
    const list: InstalledPlugin[] = [];
    for (const item of this.installed) {
      if (item.manifest.nsfw && !this.showNsfw) {
        continue;
      }
      if (this.matchesQuery(item.manifest.name, item.manifest.key) &&
        this.matchesType(item.manifest.contentType)) {
        list.push(item);
      }
    }
    this.shownInstalled = list;
  }

  filteredRepoEntries(): RepoEntry[] {
    const list: RepoEntry[] = [];
    for (const entry of this.repoEntries) {
      if (entry.nsfw && !this.showNsfw) {
        continue;
      }
      if (this.matchesQuery(entry.name, entry.key) && this.matchesType(entry.contentType)) {
        list.push(entry);
      }
    }
    return list;
  }

  private installedVersionOf(key: string): number {
    for (const item of this.installed) {
      if (item.manifest.key === key) {
        return item.manifest.versionCode;
      }
    }
    return -1;
  }

  private async refreshRepo(): Promise<void> {
    if (this.repoUrl === '' || this.loadingRepo) {
      return;
    }
    this.loadingRepo = true;
    try {
      const entries = await PluginService.fetchRepo(this.repoUrl);
      if (this.disposed) {
        return;
      }
      this.repoEntries = entries;
    } catch (e) {
      if (this.disposed) {
        return;
      }
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_repo_load_failed'),
        [Util.errText(this.getUIContext(), (e as Error).message)]);
    }
    if (!this.disposed) {
      this.loadingRepo = false;
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
      const key = await PluginService.installFromFile(uri);
      if (this.disposed) {
        return;
      }
      this.refreshInstalled();
      PluginService.markDirty();
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_installed'), [key]);
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

  private async installFromRepo(entry: RepoEntry): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await PluginService.installFromRepo(entry);
      if (this.disposed) {
        return;
      }
      this.refreshInstalled();
      PluginService.markDirty();
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_installed_name'), [entry.name]);
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

  @Builder
  pluginRow(item: InstalledPlugin) {
    Row() {
      TypeBadgedIcon({
        iconPath: item.iconPath,
        fallbackChar: this.firstCharOf(item.manifest.name),
        iconSize: 40,
        cornerRadius: 10,
        contentType: item.manifest.contentType,
        badgeBorder: this.pal.card,
      })

      Column() {
        Text(item.manifest.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(`${item.manifest.key} · v${item.manifest.version} · ${item.manifest.lang}`)
            .fontSize(11)
            .fontColor(this.pal.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.manifest.nsfw) {
            NsfwTag()
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      this.onOpenPlugin(item.manifest.key);
    })
  }

  @Builder
  repoRow(entry: RepoEntry) {
    Row() {
      TypeBadgedIcon({
        iconPath: entry.icon,
        fallbackChar: this.firstCharOf(entry.name),
        iconSize: 40,
        cornerRadius: 10,
        contentType: entry.contentType,
        badgeBorder: this.pal.card,
      })

      Column() {
        Text(entry.name)
          .fontSize(14)
          .fontColor(this.pal.text)
        Row() {
          Text(`v${entry.version} · ${entry.lang}`)
            .fontSize(11)
            .fontColor(this.pal.sub)
          if (entry.nsfw) {
            NsfwTag()
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      // 安装前预览插件对应网站（仓库索引声明 site 时显示）
      if (entry.site !== '') {
        AppIcon({ name: 'public', iconSize: 20, tint: this.pal.sub })
          .padding({ left: 8, right: 4, top: 8, bottom: 8 })
          .onClick(() => {
            this.previewSiteUrl = entry.site;
            this.previewName = entry.name;
            this.showSitePreview = true;
          })
      }

      if (this.installedVersionOf(entry.key) < 0) {
        Text($r('app.string.common_install'))
          .fontSize(13)
          .fontColor(this.pal.primary)
          .padding(4)
          .onClick(() => {
            this.installFromRepo(entry);
          })
      } else if (this.installedVersionOf(entry.key) < entry.versionCode) {
        Text($r('app.string.common_update'))
          .fontSize(13)
          .fontColor('#E08A3C')
          .padding(4)
          .onClick(() => {
            this.installFromRepo(entry);
          })
      } else {
        Text($r('app.string.plugin_up_to_date'))
          .fontSize(12)
          .fontColor(this.pal.sub)
          .padding(4)
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
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
    Scroll() {
      Column() {
        // 已安装
        Column() {
          Text($r('app.string.plugin_installed_section'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .width('100%')
            .margin({ bottom: 4 })

          if (this.shownInstalled.length === 0) {
            EmptyScreen({
              message: this.searchQuery.trim() !== '' || this.typeFilter.length > 0 ?
                $r('app.string.ext_search_no_match') :
                $r('app.string.plugin_empty'),
              compact: true,
            })
          } else {
            ForEach(this.shownInstalled, (item: InstalledPlugin) => {
              this.pluginRow(item)
            }, (item: InstalledPlugin) => `plug-${item.manifest.key}-${item.manifest.versionCode}-${item.iconPath}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.pal.card)
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 4 })

        // 在线仓库
        Column() {
          Text($r('app.string.plugin_repo'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .width('100%')
            .margin({ bottom: 4 })

          if (this.repoUrl === '') {
            Text($r('app.string.plugin_repo_hint'))
              .fontSize(12)
              .fontColor(this.pal.sub)
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else if (this.loadingRepo) {
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
            .padding({ top: 10, bottom: 10 })
          } else if (this.filteredRepoEntries().length === 0) {
            Text($r('app.string.ext_search_no_match'))
              .fontSize(12)
              .fontColor(this.pal.sub)
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            ForEach(this.filteredRepoEntries(), (entry: RepoEntry) => {
              this.repoRow(entry)
            }, (entry: RepoEntry) => `repo-${entry.key}-${entry.versionCode}-${entry.icon}`)
          }

          if (this.repoUrl !== '') {
            Text(this.repoUrl)
              .fontSize(10)
              .fontColor(this.pal.sub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 6 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.pal.card)
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 12, bottom: 24 })
      }
      .width('100%')
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
    .contentEndOffset(this.navBarH + this.tabPadH)
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSitePreview, this.sitePreviewBuilder(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      preferType: Bp.sheetType(this.windowW),
      width: Bp.sheetWidth(this.windowW, 560),
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      maskColor: 'rgba(0,0,0,0.45)',
    })
  }
}
