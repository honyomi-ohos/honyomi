import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { PluginService, InstalledPlugin, RepoEntry } from '../../data/PluginService';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { Settings } from '../../common/Settings';
import { InputDialog } from './Dialogs';
import { EmptyScreen } from './EmptyScreen';

// 插件列表面板（浏览页“插件”Tab 内嵌）：已安装 / 从文件安装 / 在线仓库
// 仓库配置与刷新由宿主（BrowsePage 菜单）通过 AppStorage 'extRepoRefresh' 计数驱动
@Component
export struct ExtensionListPanel {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('extRepoRefresh') @Watch('onRepoRefresh') extRepoRefresh: number = 0;
  @Prop searchQuery: string = '';
  @State installed: InstalledPlugin[] = [];
  @State repoEntries: RepoEntry[] = [];
  @State repoUrl: string = '';
  @State loadingRepo: boolean = false;
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.refreshInstalled();
    this.repoUrl = Settings.getPluginRepoUrl();
    if (this.repoUrl !== '') {
      this.refreshRepo();
    }
  }

  // 宿主改仓库地址或手动刷新后触发
  private onRepoRefresh(): void {
    this.repoUrl = Settings.getPluginRepoUrl();
    this.repoEntries = [];
    if (this.repoUrl !== '') {
      this.refreshRepo();
    }
  }

  private refreshInstalled(): void {
    this.installed = PluginService.listInstalled();
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

  filteredInstalled(): InstalledPlugin[] {
    const list: InstalledPlugin[] = [];
    for (const item of this.installed) {
      if (this.matchesQuery(item.manifest.name, item.manifest.key)) {
        list.push(item);
      }
    }
    return list;
  }

  filteredRepoEntries(): RepoEntry[] {
    const list: RepoEntry[] = [];
    for (const entry of this.repoEntries) {
      if (this.matchesQuery(entry.name, entry.key)) {
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
      this.repoEntries = await PluginService.fetchRepo(this.repoUrl);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_repo_load_failed'), [(e as Error).message]);
    }
    this.loadingRepo = false;
  }

  private async pickPluginFile(): Promise<void> {
    if (this.busy) {
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.mihonplug', '.zip'];
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
      this.refreshInstalled();
      PluginService.markDirty();
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_installed'), [key]);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_install_failed'), [(e as Error).message]);
    }
    this.busy = false;
  }

  private async togglePlugin(item: InstalledPlugin, on: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await PluginService.setEnabled(item.manifest.key, on);
      this.refreshInstalled();
      PluginService.markDirty();
    } catch (e) {
      this.refreshInstalled();
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_action_failed'));
    }
    this.busy = false;
  }

  private async uninstallPlugin(item: InstalledPlugin): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await PluginService.uninstall(item.manifest.key);
      this.refreshInstalled();
      PluginService.markDirty();
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_uninstalled'), [item.manifest.name]);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_uninstall_failed'));
    }
    this.busy = false;
  }

  private async installFromRepo(entry: RepoEntry): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await PluginService.installFromRepo(entry);
      this.refreshInstalled();
      PluginService.markDirty();
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_installed_name'), [entry.name]);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.plugin_install_failed'), [(e as Error).message]);
    }
    this.busy = false;
  }

  @Builder
  pluginRow(item: InstalledPlugin) {
    Column() {
      Row() {
        if (item.iconPath !== '') {
          Image(item.iconPath)
            .width(40)
            .height(40)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .clip(true)
        } else {
          Text(this.firstCharOf(item.manifest.name))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .width(40)
            .height(40)
            .borderRadius(10)
            .backgroundColor(this.pal.primary)
        }

        Column() {
          Text(item.manifest.name)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
          Text(`${item.manifest.key} · v${item.manifest.version} · ${item.manifest.lang}`)
            .fontSize(11)
            .fontColor(this.pal.sub)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

        Toggle({ type: ToggleType.Switch, isOn: item.enabled })
          .onChange((on: boolean) => {
            this.togglePlugin(item, on);
          })
      }
      .width('100%')

      Row() {
        Text($r('app.string.common_uninstall'))
          .fontSize(12)
          .fontColor('#E05252')
          .padding({ top: 6, bottom: 2, left: 4, right: 4 })
          .onClick(() => {
            this.uninstallPlugin(item);
          })
        Text($r('app.string.plugin_disable_hint'))
          .fontSize(10)
          .fontColor(this.pal.sub)
          .margin({ left: 12 })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  repoRow(entry: RepoEntry) {
    Row() {
      Column() {
        Text(entry.name)
          .fontSize(14)
          .fontColor(this.pal.text)
        Text(`v${entry.version} · ${entry.lang}`)
          .fontSize(11)
          .fontColor(this.pal.sub)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

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

          if (this.filteredInstalled().length === 0) {
            EmptyScreen({
              message: this.searchQuery.trim() !== '' ? $r('app.string.ext_search_no_match') :
                $r('app.string.plugin_empty'),
              compact: true,
            })
          } else {
            ForEach(this.filteredInstalled(), (item: InstalledPlugin) => {
              this.pluginRow(item)
            }, (item: InstalledPlugin) => `plug-${item.manifest.key}-${item.enabled}-${item.iconPath}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.pal.card)
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 4 })

        // 从文件安装
        Column() {
          Text($r('app.string.plugin_local_install'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .width('100%')
            .margin({ bottom: 8 })
          Button(this.busy ? $r('app.string.plugin_processing') : $r('app.string.plugin_install_from_file'))
            .fontSize(14)
            .width('100%')
            .backgroundColor(this.pal.primary)
            .onClick(() => {
              this.pickPluginFile();
            })
          Text($r('app.string.plugin_package_hint'))
            .fontSize(11)
            .fontColor(this.pal.sub)
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .backgroundColor(this.pal.card)
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 12 })

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
            }, (entry: RepoEntry) => `repo-${entry.key}-${entry.versionCode}`)
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
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
    .contentEndOffset(this.navBarH + 76)
    .width('100%')
    .height('100%')
  }
}
