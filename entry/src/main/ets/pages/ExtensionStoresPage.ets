import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PluginService, RepoStoreInfo } from '../data/PluginService';
import { PluginStoreRecord, Settings } from '../common/Settings';
import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Util } from '../common/Util';
import { AppKeys } from '../common/AppKeys';
import { AppIcon } from './components/AppIcon';
import { EmptyScreen } from './components/EmptyScreen';
import { ConfirmDialog } from './components/Dialogs';

const DOMAIN = 0x0001;
const TAG = 'Mihon';

// 添加仓库弹窗：地址输入 + 已存在校验 + 拉取索引校验（处理中/失败态）
// 对齐 Mihon ExtensionStoreCreateDialog
@Component
struct ExtStoreAddDialog {
  existingUrls: string[] = [];
  @State urlText: string = '';
  @State processing: boolean = false;
  @State errorText: string = '';
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  closeDialog: () => void = () => {
  };
  onAdded: (store: PluginStoreRecord) => void = (_s: PluginStoreRecord) => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.ext_stores_add_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)

      TextInput({
        placeholder: $r('app.string.ext_stores_url_hint'),
        text: this.urlText,
      })
        .defaultFocus(true)
        .onChange((value: string) => {
          this.urlText = value;
          if (this.errorText !== '') {
            this.errorText = '';
          }
        })

      // 辅助文案：错误信息优先，否则提示已存在/必填
      Text(this.supportText())
        .fontSize(12)
        .fontColor(this.hasError() ? '#E05252' : this.pal.sub)
        .width('100%')

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .enabled(!this.processing)
          .onClick(() => {
            this.dismiss();
          })
        Button(this.processing ? $r('app.string.ext_stores_processing') : $r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .enabled(!this.processing && this.urlText.trim() !== '')
          .onClick(() => {
            this.confirmAdd();
          })
      }
      .width('100%')

      if (this.processing) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(this.pal.primary)
      }
    }
    .padding(20)
    .width('100%')
  }

  // 输入辅助/错误文案：错误 > 已存在 > 输入提示
  private supportText(): string {
    if (this.errorText !== '') {
      return this.errorText;
    }
    const url = this.urlText.trim();
    if (this.existingUrls.indexOf(url) >= 0) {
      return Util.resStr(this.getUIContext(), $r('app.string.ext_stores_already_exists'));
    }
    return Util.resStr(this.getUIContext(), $r('app.string.ext_stores_url_label'));
  }

  private hasError(): boolean {
    return this.errorText !== '' || this.existingUrls.indexOf(this.urlText.trim()) >= 0;
  }

  private async confirmAdd(): Promise<void> {
    if (this.processing) {
      return;
    }
    const url = this.urlText.trim();
    if (!new RegExp('^https?://.+').test(url)) {
      this.errorText = Util.resStr(this.getUIContext(), $r('app.string.ext_stores_url_invalid'));
      return;
    }
    if (this.existingUrls.indexOf(url) >= 0) {
      this.errorText = Util.resStr(this.getUIContext(), $r('app.string.ext_stores_already_exists'));
      return;
    }
    this.processing = true;
    try {
      const info: RepoStoreInfo = await PluginService.fetchStoreInfo(url);
      const record: PluginStoreRecord = { url: info.url, name: info.name, website: info.website };
      this.dismiss();
      this.onAdded(record);
    } catch (e) {
      const err = e as Error;
      // 诊断日志：完整错误对象 + 堆栈（定位"undefined is not callable"具体调用点）
      hilog.error(DOMAIN, TAG, 'addRepo failed: name=%{public}s msg=%{public}s', err.name, err.message);
      hilog.error(DOMAIN, TAG, 'addRepo stack: %{public}s', err.stack ?? '');
      this.processing = false;
      this.errorText = Util.resStr(this.getUIContext(), $r('app.string.ext_stores_add_failed'),
        [Util.errText(this.getUIContext(), err.message)]);
    }
  }

  private dismiss(): void {
    this.closeDialog();
    this.onClose();
  }
}

// 插件仓库管理页（对齐 Mihon ExtensionStoresScreen）：
// - 仓库卡片列表：名称 + 地址 + 复制/删除操作
// - 右下角 FAB 添加仓库（拉取索引校验后保存）
// - 顶栏刷新：重新拉取各仓库索引更新展示名
// - 删除仅移除仓库记录，已安装插件保留（对齐 Mihon deleteRepo）
@Component
export struct ExtensionStoresPage {
  @Consume('navStack') pathStack: NavPathStack;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State stores: PluginStoreRecord[] = [];
  @State refreshing: boolean = false;
  // 当前 openCustomDialog 弹窗 id（关闭用；-1 = 无弹窗）
  private activeDialogId: number = -1;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.stores = Settings.getPluginStores();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏：返回 + 标题 + 刷新
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 24 })
            .onClick(() => {
              this.pathStack.pop();
            })
          Text($r('app.string.ext_stores_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .margin({ left: 8 })
            .layoutWeight(1)
          if (this.refreshing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(this.pal.primary)
              .margin({ right: 10 })
          }
          AppIcon({ name: 'refresh', iconSize: 22 })
            .padding({ left: 8, right: 4 })
            .onClick(() => {
              this.refreshStores();
            })
        }
        .width('100%')
        .padding({
          left: 16 + this.inset(),
          right: 16 + this.inset(),
          top: this.statusBarH + 10,
          bottom: 8
        })

        // 主体：空态 / 仓库卡片列表 + FAB
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (this.stores.length === 0) {
            Column() {
              EmptyScreen({ message: $r('app.string.ext_stores_empty') })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column() {
                ForEach(this.stores, (store: PluginStoreRecord) => {
                  this.storeCard(store)
                }, (store: PluginStoreRecord) => `store-${store.url}-${store.name}`)
              }
              .width('100%')
              .padding({
                left: 16 + this.inset(),
                right: 16 + this.inset(),
                bottom: 16
              })
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Auto)
            .align(Alignment.Top)
            .contentEndOffset(this.navBarH)
          }

          // FAB：添加仓库
          Column() {
            AppIcon({ name: 'add', iconSize: 26, tint: this.pal.onPrimary })
          }
          .width(56)
          .height(56)
          .borderRadius(28)
          .backgroundColor(this.pal.primary)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ right: 24 + this.inset(), bottom: 24 })
          .shadow({ radius: 8, color: 'rgba(0,0,0,0.3)', offsetY: 4 })
          .onClick(() => {
            this.showAddDialog();
          })
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }

  // 仓库卡片：名称行 + 操作行（官网/复制/删除），对齐 Mihon ExtensionStoresListItem
  @Builder
  storeCard(store: PluginStoreRecord) {
    Column() {
      Row() {
        AppIcon({ name: 'label', iconSize: 20, tint: this.pal.primary })
        Text(store.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 10 })
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 14, left: 16, right: 16 })

      Row() {
        Column() {
        }
        .layoutWeight(1)

        // 打开仓库官网（索引声明 website 时显示）
        if (store.website !== '') {
          AppIcon({ name: 'public', iconSize: 20, tint: this.pal.sub })
            .padding({
              left: 10,
              right: 10,
              top: 8,
              bottom: 8
            })
            .onClick(() => {
              this.openWebsite(store.website);
            })
        }

        AppIcon({ name: 'content_copy', iconSize: 20, tint: this.pal.sub })
          .padding({
            left: 10,
            right: 10,
            top: 8,
            bottom: 8
          })
          .onClick(() => {
            this.copyStoreUrl(store.url);
          })

        AppIcon({ name: 'delete', iconSize: 20, tint: '#E05252' })
          .padding({
            left: 10,
            right: 10,
            top: 8,
            bottom: 8
          })
          .onClick(() => {
            this.confirmDelete(store);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .padding({
        left: 8,
        right: 8,
        top: 6,
        bottom: 6
      })
    }
    .width('100%')
    .backgroundColor(this.pal.card)
    .borderRadius(14)
    .margin({ top: 10 })
  }

  @Builder
  addDialogBuilder() {
    ExtStoreAddDialog({
      existingUrls: this.storeUrls(),
      closeDialog: (): void => {
        this.closeActiveDialog();
      },
      onAdded: (store: PluginStoreRecord): void => {
        this.onStoreAdded(store);
      },
    })
  }

  // 大屏限宽缩进：与全局限宽内容列对齐
  private inset(): number {
    return Bp.contentInset(this.windowW);
  }

  private reload(): void {
    this.stores = Settings.getPluginStores();
  }

  // 添加仓库成功后：保存 + 通知插件面板刷新
  private onStoreAdded(store: PluginStoreRecord): void {
    Settings.addPluginStore(store);
    this.reload();
    this.publishRepoChange();
    Util.toastRes(this.getUIContext(), $r('app.string.ext_stores_added'));
  }

  private confirmDelete(store: PluginStoreRecord): void {
    const dialog = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.ext_stores_delete_title'),
        message: Util.resStr(this.getUIContext(), $r('app.string.ext_stores_delete_body'),
          [store.name, store.url]),
        confirmText: $r('app.string.common_delete'),
        onConfirm: (): void => {
          this.deleteStore(store.url);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private deleteStore(url: string): void {
    Settings.removePluginStore(url);
    this.reload();
    this.publishRepoChange();
    Util.toastRes(this.getUIContext(), $r('app.string.ext_stores_deleted'));
  }

  // 顶栏刷新：重新拉取各仓库索引更新展示名（对齐 Mihon refreshRepos）
  private async refreshStores(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    const snapshot = Settings.getPluginStores();
    if (snapshot.length === 0) {
      return;
    }
    this.refreshing = true;
    let firstError = '';
    const updated: PluginStoreRecord[] = [];
    for (const store of snapshot) {
      try {
        const info: RepoStoreInfo = await PluginService.fetchStoreInfo(store.url);
        updated.push({ url: info.url, name: info.name, website: info.website });
      } catch (e) {
        // 拉取失败的仓库保留原记录
        updated.push(store);
        if (firstError === '') {
          firstError = Util.errText(this.getUIContext(), (e as Error).message);
        }
      }
    }
    if (this.disposed) {
      return;
    }
    Settings.setPluginStores(updated);
    this.reload();
    this.publishRepoChange();
    this.refreshing = false;
    if (firstError !== '') {
      Util.toastRes(this.getUIContext(), $r('app.string.ext_stores_refresh_failed'), [firstError]);
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.ext_stores_refreshed'));
    }
  }

  private copyStoreUrl(url: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => {
        if (!this.disposed) {
          Util.toastRes(this.getUIContext(), $r('app.string.ext_stores_copied'));
        }
      })
      .catch((_e: BusinessError) => {
      });
  }

  // 打开仓库官网（对齐 Mihon onOpenWebsite）
  private openWebsite(website: string): void {
    const context = Util.hostAbilityContext(this.getUIContext());
    Util.openUrl(context, website);
  }

  private showAddDialog(): void {
    this.getUIContext()
      .getPromptAction()
      .openCustomDialog({
        builder: (): void => {
          this.addDialogBuilder();
        },
        autoCancel: true,
      })
      .then((dialogId: number) => {
        this.activeDialogId = dialogId;
      })
      .catch((_e: BusinessError) => {
      });
  }

  private storeUrls(): string[] {
    const urls: string[] = [];
    for (const s of this.stores) {
      urls.push(s.url);
    }
    return urls;
  }

  private closeActiveDialog(): void {
    if (this.activeDialogId < 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(this.activeDialogId);
    } catch (_e) {
    }
    this.activeDialogId = -1;
  }

  // 仓库增删改后通知插件列表面板重新拉取
  private publishRepoChange(): void {
    AppStorage.setOrCreate(AppKeys.EXT_REPO_REFRESH,
      (AppStorage.get<number>(AppKeys.EXT_REPO_REFRESH) ?? 0) + 1);
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function ExtensionStoresBuilder() {
  ExtensionStoresPage()
}
