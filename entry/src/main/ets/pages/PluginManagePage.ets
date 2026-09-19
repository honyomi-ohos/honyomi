import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { PluginService, InstalledPlugin, RepoEntry } from '../data/PluginService';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { InputDialog } from './components/Dialogs';

// 插件管理页：已安装列表 / 启停 / 卸载 / 从文件安装 / 在线仓库
@Component
export struct PluginManagePage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @State installed: InstalledPlugin[] = [];
  @State repoEntries: RepoEntry[] = [];
  @State repoUrl: string = '';
  @State loadingRepo: boolean = false;
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.installed = PluginService.listInstalled();
    this.repoUrl = Settings.getPluginRepoUrl();
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
      Util.toast(this.getUIContext(), `仓库加载失败：${(e as Error).message}`);
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
      Util.toast(this.getUIContext(), '选择文件失败');
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
      Util.toast(this.getUIContext(), `已安装插件：${key}`);
    } catch (e) {
      Util.toast(this.getUIContext(), `安装失败：${(e as Error).message}`);
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
      Util.toast(this.getUIContext(), '操作失败');
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
      Util.toast(this.getUIContext(), `已卸载 ${item.manifest.name}（数据保留）`);
    } catch (e) {
      Util.toast(this.getUIContext(), '卸载失败');
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
      Util.toast(this.getUIContext(), `已安装：${entry.name}`);
    } catch (e) {
      Util.toast(this.getUIContext(), `安装失败：${(e as Error).message}`);
    }
    this.busy = false;
  }

  private showRepoUrlDialog(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: '插件仓库索引 URL',
        placeholder: 'https://…/index.json（留空清除）',
        onConfirm: (text: string): void => {
          this.repoUrl = text.trim();
          Settings.setPluginRepoUrl(this.repoUrl);
          this.repoEntries = [];
          if (this.repoUrl !== '') {
            this.refreshRepo();
          }
        },
      }),
      autoCancel: true,
    });
    dialog.open();
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
        Text('卸载')
          .fontSize(12)
          .fontColor('#E05252')
          .padding({ top: 6, bottom: 2, left: 4, right: 4 })
          .onClick(() => {
            this.uninstallPlugin(item);
          })
        Text('禁用后将从源列表隐藏，卸载不删除已收藏漫画')
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
        Text('安装')
          .fontSize(13)
          .fontColor(this.pal.primary)
          .padding(4)
          .onClick(() => {
            this.installFromRepo(entry);
          })
      } else if (this.installedVersionOf(entry.key) < entry.versionCode) {
        Text('更新')
          .fontSize(13)
          .fontColor('#E08A3C')
          .padding(4)
          .onClick(() => {
            this.installFromRepo(entry);
          })
      } else {
        Text('已最新')
          .fontSize(12)
          .fontColor(this.pal.sub)
          .padding(4)
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    NavDestination() {
      Column() {
        // 头部
        Row() {
          Text('‹')
            .fontSize(30)
            .fontColor(this.pal.text)
            .onClick(() => {
              this.pathStack.pop();
            })
          Text('插件管理')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.statusBarH + 10, bottom: 10 })

        Scroll() {
          Column() {
            // 已安装
            Column() {
              Text('已安装插件')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal.text)
                .width('100%')
                .margin({ bottom: 4 })

              if (this.installed.length === 0) {
                Text('暂无插件，从下方安装')
                  .fontSize(12)
                  .fontColor(this.pal.sub)
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
              } else {
                ForEach(this.installed, (item: InstalledPlugin) => {
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
              Text('本地安装')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.pal.text)
                .width('100%')
                .margin({ bottom: 8 })
              Button(this.busy ? '处理中…' : '从文件安装（.mihonplug）')
                .fontSize(14)
                .width('100%')
                .backgroundColor(this.pal.primary)
                .onClick(() => {
                  this.pickPluginFile();
                })
              Text('插件包 = manifest.json + main.js 打包的 zip 文件')
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
              Row() {
                Text('插件仓库')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal.text)
                  .layoutWeight(1)
                Text(this.repoUrl === '' ? '配置' : '刷新')
                  .fontSize(13)
                  .fontColor(this.pal.primary)
                  .padding(4)
                  .onClick(() => {
                    if (this.repoUrl === '') {
                      this.showRepoUrlDialog();
                    } else {
                      this.refreshRepo();
                    }
                  })
              }
              .width('100%')
              .margin({ bottom: 4 })

              if (this.repoUrl === '') {
                Text('配置仓库索引 URL 后可在线安装/更新插件')
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
                  Text('加载仓库中…')
                    .fontSize(12)
                    .fontColor(this.pal.sub)
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
              } else {
                ForEach(this.repoEntries, (entry: RepoEntry) => {
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
                  .onClick(() => {
                    this.showRepoUrlDialog();
                  })
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
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }
}
