// 追踪弹层（对齐 Mihon TrackSheet）：三模式
// - 列表：8 个追踪器登录/绑定状态，未登录拉起 OAuth 或账密登录，已登录未绑定进入搜索
// - 搜索：按标题在所选追踪器搜索并注册绑定
// - 详情：状态/章节/评分/日期/私密编辑与解绑/远端删除
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { KeyCode } from '@kit.InputKit';
import { SheetPreset } from './SheetPreset';
import { MangaRecord, TrackRecord, TrackSearchResult } from '../../model/Models';
import { MangaRepo, TrackRepo } from '../../data/Repos';
import { Tracker } from '../../data/track/Tracker';
import { TrackerManager } from '../../data/track/TrackerManager';
import { TrackLogo } from './TrackLogo';
import { OAuthSheet } from './OAuthSheet';
import { PickerSheet } from './PickerSheet';
import { SmartImage } from './SmartImage';
import { CredentialsDialog, InputDialog } from './Dialogs';
import { AppIcon } from './AppIcon';

// 弹层模式
const MODE_LIST: number = 0;
const MODE_SEARCH: number = 1;
const MODE_DETAIL: number = 2;

// 日期选择目标
const DATE_START: number = 0;
const DATE_FINISH: number = 1;

// 服务器地址登录弹窗（自托管追踪器 Komga/Kavita/Suwayomi 专用）：
// 服务器地址必填；用户名/密钥字段按占位符显示（空占位符表示隐藏该字段）
@CustomDialog
export struct ServerLoginDialog {
  controller?: CustomDialogController;
  title: Resource | string = '';
  serverPlaceholder: Resource | string = '';
  userPlaceholder: Resource | string = '';
  secretPlaceholder: Resource | string = '';
  initialServer: string = '';
  @State serverUrl: string = '';
  @State username: string = '';
  @State secret: string = '';
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  onConfirm: (serverUrl: string, username: string, secret: string) => void =
    (_s: string, _u: string, _p: string) => {
    };
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    this.serverUrl = this.initialServer;
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      TextInput({
        placeholder: this.serverPlaceholder,
        text: this.serverUrl,
      })
        .defaultFocus(true)
        .enterKeyType(EnterKeyType.Next)
        .onChange((value: string) => {
          this.serverUrl = value;
        })
        .onSubmit(() => {
          // 服务器地址回车跳下一输入框（手动迁移焦点，失败时仍可 Tab 切换）
          try {
            this.getUIContext().getFocusController().requestFocus('serverUserKey');
          } catch (_e) {
          }
        })
      if (this.userPlaceholder !== '') {
        TextInput({
          placeholder: this.userPlaceholder,
          text: this.username,
        })
          .key('serverUserKey')
          .enterKeyType(EnterKeyType.Next)
          .onChange((value: string) => {
            this.username = value;
          })
          .onSubmit(() => {
            try {
              this.getUIContext().getFocusController().requestFocus('serverSecretKey');
            } catch (_e) {
            }
          })
      }
      if (this.secretPlaceholder !== '') {
        TextInput({
          placeholder: this.secretPlaceholder,
          text: this.secret,
        })
          .type(InputType.Password)
          .key('serverSecretKey')
          .enterKeyType(EnterKeyType.Done)
          .onChange((value: string) => {
            this.secret = value;
          })
          .onSubmit(() => {
            this.dismiss();
            this.onConfirm(this.serverUrl.trim(), this.username.trim(), this.secret);
          })
      }
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.dismiss();
          })
        Button($r('app.string.common_ok'))
          .layoutWeight(1)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.dismiss();
            this.onConfirm(this.serverUrl.trim(), this.username.trim(), this.secret);
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
        this.dismiss();
      }
    })
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
    this.onClose();
  }
}

@Component
export struct TrackSheet {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  mangaId: number = -1;
  mangaTitle: string = '';
  hasReadChapters: boolean = false;
  // 模式
  @State mode: number = MODE_LIST;
  // 当前漫画的追踪记录
  @State tracks: TrackRecord[] = [];
  // 详情/搜索模式的当前追踪记录（syncId=0 哨兵表示未绑定）
  @State selTrackRec: TrackRecord = new TrackRecord();
  // 登录/凭据变化计数：驱动追踪器行刷新（登录态读取自 Settings，非响应式）
  @State loginTick: number = 0;
  @State busy: boolean = false;
  // 搜索模式
  @State selSyncId: number = 0;
  @State searchQuery: string = '';
  @State searching: boolean = false;
  @State searchResults: TrackSearchResult[] = [];
  // OAuth 授权弹层
  @State showOAuth: boolean = false;
  @State oauthUrl: string = '';
  @State oauthTitle: string = '';
  // 详情模式选择器
  @State showStatusPicker: boolean = false;
  @State showScorePicker: boolean = false;
  @State showRemovePicker: boolean = false;
  // 详情/搜索模式的当前追踪器（注册表单例，身份不变）
  private selTrackerInst: Tracker = TrackerManager.myAnimeList;
  private oauthSyncId: number = 0;
  private dateTarget: number = DATE_START;
  onChanged: () => void = () => {
  };
  onClose: () => void = () => {
  };

  aboutToAppear(): void {
    this.refreshTracks();
  }

  // ----- 数据 -----

  @Builder
  trackerRow(t: Tracker, track: TrackRecord | undefined) {
    Row() {
      TrackLogo({
        syncId: t.syncId,
        logoName: t.name,
        color: t.brandColor,
        logoSize: 30
      })
        .margin({ right: 14 })
      Column() {
        Text(t.name)
          .fontSize(16)
          .fontColor(this.pal.text)
          .maxLines(1)
        if (!t.isLoggedIn()) {
          Text($r('app.string.track_login'))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (track !== undefined) {
        Column() {
          Text(t.getStatusLabel(track.status))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(1)
          Text(this.trackSummaryText(t, track))
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(1)
            .margin({ top: 1 })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ right: 6 })
      } else if (t.isLoggedIn()) {
        AppIcon({ name: 'add', iconSize: 22, tint: this.pal.primary })
      } else {
        AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({
      left: 16,
      right: 12,
      top: 8,
      bottom: 8
    })
    .onClick(() => {
      this.onTrackerTap(t);
    })
  }

  @Builder
  trackerList() {
    List({ space: 0 }) {
      ForEach(TrackerManager.trackers, (t: Tracker) => {
        ListItem() {
          this.trackerRow(t, this.trackOf(t.syncId))
        }
      }, (t: Tracker): string => `tracker-${t.syncId}-${this.loginTick}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .divider({
      strokeWidth: 1,
      color: this.pal.divider,
      startMargin: 16,
      endMargin: 12,
    })
  }

  @Builder
  searchResultRow(item: TrackSearchResult) {
    Row() {
      SmartImage({
        url: item.coverUrl,
        sourceKey: `track-cover-${item.syncId}-${item.remoteId}`,
        placeholderIconSize: 18,
      })
        .width(44)
        .height(62)
        .borderRadius(8)
        .clip(true)
      Column() {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.text)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.summary !== '') {
          Text(item.summary)
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        if (this.searchItemMeta(item) !== '') {
          Text(this.searchItemMeta(item))
            .fontSize(11)
            .fontColor(this.pal.sub)
            .maxLines(1)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12, right: 8 })

      AppIcon({ name: 'add', iconSize: 22, tint: this.pal.primary })
        .onClick(() => {
          this.registerItem(item);
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
  }

  @Builder
  searchBody() {
    Column() {
      Row({ space: 8 }) {
        AppIcon({ name: 'search', iconSize: 20, tint: this.pal.sub })
        TextInput({
          placeholder: Util.resStr(this.getUIContext(), $r('app.string.track_search_hint'),
            [this.selTrackerInst.name]),
          text: this.searchQuery,
        })
          .fontSize(15)
          .fontColor(this.pal.text)
          .placeholderColor(this.pal.sub)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.searchQuery = value;
          })
          .onSubmit(() => {
            this.doSearch(this.searchQuery);
          })
        if (this.searchQuery !== '') {
          AppIcon({ name: 'close', iconSize: 18, tint: this.pal.sub })
            .onClick(() => {
              this.searchQuery = '';
              this.searchResults = [];
            })
        }
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 4,
        bottom: 10
      })

      if (this.searching) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.pal.primary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.searchResults, (item: TrackSearchResult) => {
            ListItem() {
              this.searchResultRow(item)
            }
          }, (item: TrackSearchResult): string => `sr-${item.syncId}-${item.remoteId}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({
          strokeWidth: 1,
          color: this.pal.divider,
          startMargin: 16,
          endMargin: 16,
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ----- 列表模式：追踪器行点击 -----

  @Builder
  detailBody() {
    Scroll() {
      Column() {
        Text(this.selTrackRec.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ bottom: 6 })

        Column() {
          // 状态
          Row() {
            Text($r('app.string.track_status'))
              .fontSize(15)
              .fontColor(this.pal.text)
              .layoutWeight(1)
              .maxLines(1)
            Text(this.selTrackerInst.getStatusLabel(this.selTrackRec.status))
              .fontSize(14)
              .fontColor(this.pal.sub)
              .maxLines(1)
            AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
              .margin({ left: 4 })
          }
          .width('100%')
          .height(50)
          .padding({ left: 16, right: 12 })
          .onClick(() => {
            this.showStatusPicker = true;
          })
          .bindSheet($$this.showStatusPicker, this.statusPickerBuilder(),
            SheetPreset.fit(this.windowW, { showClose: false, bg: this.pal.bg }))

          Divider().color(this.pal.divider).margin({ left: 16 })

          // 章节
          Row() {
            Text($r('app.string.track_chapters'))
              .fontSize(15)
              .fontColor(this.pal.text)
              .layoutWeight(1)
              .maxLines(1)
            Text(`${this.selTrackRec.lastChapterRead}`)
              .fontSize(14)
              .fontColor(this.pal.sub)
              .maxLines(1)
            AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
              .margin({ left: 4 })
          }
          .width('100%')
          .height(50)
          .padding({ left: 16, right: 12 })
          .onClick(() => {
            this.editChapters();
          })

          // 评分（评分列表为空的自托管追踪器不显示，对齐 Mihon）
          if (this.selTrackerInst.getScoreList().length > 0) {
            Divider().color(this.pal.divider).margin({ left: 16 })

            Row() {
              Text($r('app.string.track_score'))
                .fontSize(15)
                .fontColor(this.pal.text)
                .layoutWeight(1)
                .maxLines(1)
              Text(this.selTrackerInst.displayScore(this.selTrackRec))
                .fontSize(14)
                .fontColor(this.pal.sub)
                .maxLines(1)
              AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
                .margin({ left: 4 })
            }
            .width('100%')
            .height(50)
            .padding({ left: 16, right: 12 })
            .onClick(() => {
              this.showScorePicker = true;
            })
            .bindSheet($$this.showScorePicker, this.scorePickerBuilder(),
              SheetPreset.fit(this.windowW, { showClose: false, bg: this.pal.bg }))
          }

          if (this.selTrackerInst.supportsReadingDates) {
            Divider().color(this.pal.divider).margin({ left: 16 })

            // 开始日期
            Row() {
              Text($r('app.string.track_start_date'))
                .fontSize(15)
                .fontColor(this.pal.text)
                .layoutWeight(1)
                .maxLines(1)
              Text(this.dateText(this.selTrackRec.startDate))
                .fontSize(14)
                .fontColor(this.pal.sub)
                .maxLines(1)
              AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
                .margin({ left: 4 })
            }
            .width('100%')
            .height(50)
            .padding({ left: 16, right: 12 })
            .onClick(() => {
              this.pickDate(DATE_START);
            })

            Divider().color(this.pal.divider).margin({ left: 16 })

            // 结束日期
            Row() {
              Text($r('app.string.track_finish_date'))
                .fontSize(15)
                .fontColor(this.pal.text)
                .layoutWeight(1)
                .maxLines(1)
              Text(this.dateText(this.selTrackRec.finishDate))
                .fontSize(14)
                .fontColor(this.pal.sub)
                .maxLines(1)
              AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
                .margin({ left: 4 })
            }
            .width('100%')
            .height(50)
            .padding({ left: 16, right: 12 })
            .onClick(() => {
              this.pickDate(DATE_FINISH);
            })
          }

          if (this.selTrackerInst.supportsPrivateTracking) {
            Divider().color(this.pal.divider).margin({ left: 16 })

            // 私密
            Row() {
              Text($r('app.string.track_private'))
                .fontSize(15)
                .fontColor(this.pal.text)
                .layoutWeight(1)
                .maxLines(1)
              Toggle({ type: ToggleType.Switch, isOn: this.selTrackRec.isPrivate })
                .selectedColor(this.pal.primary)
                .onChange((value: boolean) => {
                  this.applyPrivate(value);
                })
            }
            .width('100%')
            .height(50)
            .padding({ left: 16, right: 12 })
          }
        }
        .backgroundColor(this.pal.card)
        .borderRadius(16)
        .clip(true)
        .width('100%')

        // 解绑 / 远端删除
        Row() {
          Text($r('app.string.track_unlink'))
            .fontSize(15)
            .fontColor('#E05252')
            .layoutWeight(1)
            .maxLines(1)
          AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
            .margin({ left: 4 })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 12 })
        .backgroundColor(this.pal.card)
        .borderRadius(16)
        .margin({ top: 12 })
        .onClick(() => {
          this.showRemovePicker = true;
        })
        .bindSheet($$this.showRemovePicker, this.removePickerBuilder(),
          SheetPreset.fit(this.windowW, { showClose: false, bg: this.pal.bg }))
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 4,
        bottom: 24
      })
      .constraintSize({ maxWidth: 720 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
  }

  // ----- 登录 -----

  @Builder
  statusPickerBuilder() {
    PickerSheet({
      options: this.statusOptions(),
      selectedIndex: this.statusOptionsIndexOf(),
      onPick: (index: number): void => {
        this.showStatusPicker = false;
        this.applyStatus(index);
      },
    })
  }

  @Builder
  scorePickerBuilder() {
    PickerSheet({
      options: this.scoreOptions(),
      selectedIndex: this.scoreOptionsIndexOf(),
      onPick: (index: number): void => {
        this.showScorePicker = false;
        this.applyScore(index);
      },
    })
  }

  @Builder
  removePickerBuilder() {
    PickerSheet({
      options: [$r('app.string.track_unlink'), $r('app.string.track_remove_remote')],
      onPick: (index: number): void => {
        this.showRemovePicker = false;
        this.applyRemove(index);
      },
    })
  }

  @Builder
  oauthBuilder() {
    OAuthSheet({
      authUrl: this.oauthUrl,
      sheetTitle: this.oauthTitle,
      onOAuthResult: (params: Record<string, string>): void => {
        this.onOAuthResult(params);
      },
      onClose: (): void => {
        this.showOAuth = false;
      },
    })
  }

  build() {
    Column() {
      // 头部
      Row() {
        if (this.mode !== MODE_LIST) {
          AppIcon({ name: 'arrow_back', iconSize: 20, tint: this.pal.text })
            .width(36)
            .height(36)
            .margin({ left: -8 })
            .onClick(() => {
              this.mode = MODE_LIST;
            })
        }
        Text(this.mode === MODE_LIST ? $r('app.string.track_title') : this.selTrackerInst.name)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.mode === MODE_DETAIL && this.selTrackRec.syncId !== 0) {
          AppIcon({ name: 'refresh', iconSize: 20, tint: this.pal.text })
            .width(36)
            .height(36)
            .onClick(() => {
              this.refreshTrack();
            })
        }
        if (this.busy) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(this.pal.primary)
            .margin({ left: 6 })
        }
        AppIcon({ name: 'close', iconSize: 20, tint: this.pal.sub })
          .width(36)
          .height(36)
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({
        left: 16,
        right: 8,
        top: 6,
        bottom: 8
      })

      // 内容
      if (this.mode === MODE_LIST) {
        this.trackerList()
      } else if (this.mode === MODE_SEARCH) {
        this.searchBody()
      } else if (this.selTrackRec.syncId !== 0) {
        this.detailBody()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .bindSheet($$this.showOAuth, this.oauthBuilder(),
      SheetPreset.fit(this.windowW, {
        height: '80%',
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        showClose: false,
        maskColor: 'rgba(0,0,0,0.45)'
      }))
  }

  // ----- 搜索模式 -----

  private async refreshTracks(): Promise<void> {
    try {
      this.tracks = await TrackRepo.listByManga(this.mangaId);
    } catch (_e) {
      this.tracks = [];
    }
    this.syncSelTrack();
  }

  // 详情模式记录与 DB 刷新结果保持同步
  private syncSelTrack(): void {
    const t = this.trackOf(this.selSyncId);
    this.selTrackRec = t !== undefined ? t : new TrackRecord();
  }

  private trackOf(syncId: number): TrackRecord | undefined {
    for (const t of this.tracks) {
      if (t.syncId === syncId) {
        return t;
      }
    }
    return undefined;
  }

  // ----- 详情模式编辑 -----

  // 统一更新：busy 包装 + 落库后刷新
  private async runTrackUpdate(fn: () => Promise<TrackRecord>): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await fn();
      await this.refreshTracks();
      this.onChanged();
    } catch (_e) {
      Util.toastRes(this.getUIContext(), $r('app.string.track_update_failed'));
    }
    this.busy = false;
  }

  private onTrackerTap(t: Tracker): void {
    if (!t.isLoggedIn()) {
      this.startLogin(t);
      return;
    }
    this.selTrackerInst = t;
    this.selSyncId = t.syncId;
    const track = this.trackOf(t.syncId);
    if (track !== undefined) {
      this.selTrackRec = track;
      this.mode = MODE_DETAIL;
    } else if (t.isEnhanced) {
      // 增强型追踪器（Komga/Kavita/Suwayomi）：跳过搜索，按源自动匹配绑定
      this.selTrackRec = new TrackRecord();
      this.enhancedRegister(t);
    } else {
      this.selTrackRec = new TrackRecord();
      this.mode = MODE_SEARCH;
      this.searchQuery = this.mangaTitle;
      this.searchResults = [];
      this.doSearch(this.mangaTitle);
    }
  }

  private startLogin(t: Tracker): void {
    // 账密登录型：Kitsu / MangaUpdates
    if (t.syncId === TrackerManager.kitsu.syncId || t.syncId === TrackerManager.mangaUpdates.syncId) {
      this.showCredentialsLogin(t);
      return;
    }
    // 服务器地址登录型：Komga / Kavita / Suwayomi
    if (t.syncId === TrackerManager.komga.syncId || t.syncId === TrackerManager.kavita.syncId ||
      t.syncId === TrackerManager.suwayomi.syncId) {
      this.showServerLogin(t);
      return;
    }
    this.oauthSyncId = t.syncId;
    this.oauthTitle = t.name;
    this.busy = true;
    t.getAuthUrl().then((url: string): void => {
      this.busy = false;
      this.oauthUrl = url;
      this.showOAuth = true;
    }).catch((): void => {
      this.busy = false;
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
    });
  }

  // 增强型追踪器绑定：按漫画 sourceKey + url 自动匹配远端条目后注册（对齐 Mihon EnhancedTracker.match）
  private enhancedRegister(t: Tracker): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    MangaRepo.get(this.mangaId)
      .then((manga: MangaRecord | undefined): Promise<TrackSearchResult | undefined> => {
        if (manga === undefined) {
          return Promise.resolve<TrackSearchResult | undefined>(undefined);
        }
        return t.match(manga);
      })
      .then((item: TrackSearchResult | undefined): void => {
        if (item === undefined) {
          this.busy = false;
          Util.toastRes(this.getUIContext(), $r('app.string.track_no_results'));
          return;
        }
        t.register(item, this.mangaId, this.hasReadChapters).then((): void => {
          this.busy = false;
          this.refreshTracks();
          this.onChanged();
          this.mode = MODE_DETAIL;
          Util.toastRes(this.getUIContext(), $r('app.string.track_added'));
        }).catch((): void => {
          this.busy = false;
          Util.toastRes(this.getUIContext(), $r('app.string.track_add_failed'));
        });
      })
      .catch((): void => {
        this.busy = false;
        Util.toastRes(this.getUIContext(), $r('app.string.track_add_failed'));
      });
  }

  // 服务器地址登录：自托管追踪器（服务器地址 + 凭据，字段按追踪器显示）
  private showServerLogin(t: Tracker): void {
    let serverHint = 'http://192.168.1.1:25600';
    let userHint = '';
    let secretHint = '';
    if (t.syncId === TrackerManager.komga.syncId) {
      userHint = '邮箱 / 用户名';
      secretHint = Util.resStr(this.getUIContext(), $r('app.string.track_password'));
    } else if (t.syncId === TrackerManager.kavita.syncId) {
      serverHint = 'http://192.168.1.1:5000';
      secretHint = 'API Key（Kavita 服务器设置生成）';
    } else {
      serverHint = 'http://192.168.1.1:4567';
      userHint = '用户名（可选，Basic Auth）';
      secretHint = '密码（可选，Basic Auth）';
    }
    const dialog = new CustomDialogController({
      builder: ServerLoginDialog({
        title: t.name,
        serverPlaceholder: serverHint,
        userPlaceholder: userHint,
        secretPlaceholder: secretHint,
        initialServer: t.getUsername(),
        onConfirm: (serverUrl: string, username: string, secret: string): void => {
          this.doServerLogin(t, serverUrl, username, secret);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private doServerLogin(t: Tracker, serverUrl: string, username: string, secret: string): void {
    if (serverUrl === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
      return;
    }
    this.busy = true;
    t.loginWithServer(serverUrl, username, secret).then((): void => {
      this.busy = false;
      this.loginTick += 1;
      this.refreshTracks();
      Util.toastRes(this.getUIContext(), $r('app.string.track_logged_in'), [t.name]);
    }).catch((): void => {
      this.busy = false;
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
    });
  }

  // OAuth 回调参数 → 登录调用（各追踪器参数名不同，对齐 TrackLoginActivity）
  private oauthLoginCall(t: Tracker, params: Record<string, string>): Promise<void> {
    if (t.syncId === TrackerManager.aniList.syncId) {
      // AniList 隐式授权：token 在 fragment
      return t.loginWithCode(params['access_token'] ?? '');
    }
    if (t.syncId === TrackerManager.hikka.syncId) {
      // Hikka：reference code 经账密通道换取
      return t.loginWithCredentials('', params['reference'] ?? '');
    }
    return t.loginWithCode(params['code'] ?? '');
  }

  private onOAuthResult(params: Record<string, string>): void {
    this.showOAuth = false;
    const t = TrackerManager.get(this.oauthSyncId);
    if (t === undefined) {
      return;
    }
    this.busy = true;
    this.oauthLoginCall(t, params).then((): void => {
      this.busy = false;
      this.loginTick += 1;
      this.refreshTracks();
      Util.toastRes(this.getUIContext(), $r('app.string.track_logged_in'), [t.name]);
    }).catch((): void => {
      this.busy = false;
      t.logout();
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
    });
  }

  // 账密登录：用户名 + 密码同弹窗一次输入
  private showCredentialsLogin(t: Tracker): void {
    const dialog = new CustomDialogController({
      builder: CredentialsDialog({
        title: t.name,
        usernamePlaceholder: $r('app.string.track_username'),
        passwordPlaceholder: $r('app.string.track_password'),
        onConfirm: (username: string, password: string): void => {
          this.doCredentialsLogin(t, username, password);
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private doCredentialsLogin(t: Tracker, username: string, password: string): void {
    if (username === '' || password === '') {
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
      return;
    }
    this.busy = true;
    t.loginWithCredentials(username, password).then((): void => {
      this.busy = false;
      this.loginTick += 1;
      this.refreshTracks();
      Util.toastRes(this.getUIContext(), $r('app.string.track_logged_in'), [t.name]);
    }).catch((): void => {
      this.busy = false;
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
    });
  }

  private doSearch(query: string): void {
    const q = query.trim();
    if (q === '') {
      return;
    }
    this.searching = true;
    this.selTrackerInst.search(q).then((items: TrackSearchResult[]): void => {
      this.searchResults = items;
      this.searching = false;
      if (items.length === 0) {
        Util.toastRes(this.getUIContext(), $r('app.string.track_no_results'));
      }
    }).catch((): void => {
      this.searching = false;
      Util.toastRes(this.getUIContext(), $r('app.string.track_search_failed'));
    });
  }

  private registerItem(item: TrackSearchResult): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.selTrackerInst.register(item, this.mangaId, this.hasReadChapters).then((): void => {
      this.busy = false;
      this.refreshTracks();
      this.onChanged();
      this.mode = MODE_DETAIL;
      Util.toastRes(this.getUIContext(), $r('app.string.track_added'));
    }).catch((): void => {
      this.busy = false;
      Util.toastRes(this.getUIContext(), $r('app.string.track_add_failed'));
    });
  }

  // 搜索结果元信息行：类型 · 状态 · 站点评分 · 开始日期
  private searchItemMeta(item: TrackSearchResult): string {
    const parts: string[] = [];
    if (item.publishingType !== '') {
      parts.push(item.publishingType);
    }
    if (item.publishingStatus !== '') {
      parts.push(item.publishingStatus);
    }
    if (item.score > 0) {
      parts.push(`${item.score}`);
    }
    if (item.startDate !== '') {
      parts.push(item.startDate);
    }
    return parts.join(' · ');
  }

  private statusOptions(): ResourceStr[] {
    const options: ResourceStr[] = [];
    for (const s of this.selTrackerInst.getStatusList()) {
      options.push(this.selTrackerInst.getStatusLabel(s));
    }
    return options;
  }

  private scoreOptions(): ResourceStr[] {
    const options: ResourceStr[] = [];
    for (const s of this.selTrackerInst.getScoreList()) {
      options.push(s);
    }
    return options;
  }

  // ----- 视图 -----

  private statusOptionsIndexOf(): number {
    return this.selTrackerInst.getStatusList().indexOf(this.selTrackRec.status);
  }

  private scoreOptionsIndexOf(): number {
    return this.selTrackerInst.scoreIndex(this.selTrackRec.score);
  }

  private applyStatus(index: number): void {
    const statusList = this.selTrackerInst.getStatusList();
    if (index < 0 || index >= statusList.length) {
      return;
    }
    const status = statusList[index];
    this.runTrackUpdate((): Promise<TrackRecord> => this.selTrackerInst.setRemoteStatus(this.selTrackRec, status));
  }

  private applyScore(index: number): void {
    this.runTrackUpdate((): Promise<TrackRecord> => this.selTrackerInst.setRemoteScore(this.selTrackRec, index));
  }

  private editChapters(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.track_chapters'),
        placeholder: '',
        initialText: `${this.selTrackRec.lastChapterRead}`,
        onConfirm: (text: string): void => {
          const n = parseFloat(text.trim());
          if (isNaN(n) || n < 0) {
            Util.toastRes(this.getUIContext(), $r('app.string.track_invalid_chapters'));
            return;
          }
          this.runTrackUpdate((): Promise<TrackRecord> =>
          this.selTrackerInst.setRemoteLastChapterRead(this.selTrackRec, n));
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private pickDate(target: number): void {
    this.dateTarget = target;
    const current = target === DATE_START ? this.selTrackRec.startDate : this.selTrackRec.finishDate;
    this.getUIContext().showDatePickerDialog({
      selected: new Date(current > 0 ? current : Date.now()),
      onDateAccept: (date: Date): void => {
        this.applyDate(date.getTime());
      },
    });
  }

  private applyDate(epochMs: number): void {
    if (this.dateTarget === DATE_START) {
      this.runTrackUpdate((): Promise<TrackRecord> =>
      this.selTrackerInst.setRemoteStartDate(this.selTrackRec, epochMs));
    } else {
      this.runTrackUpdate((): Promise<TrackRecord> =>
      this.selTrackerInst.setRemoteFinishDate(this.selTrackRec, epochMs));
    }
  }

  private applyPrivate(value: boolean): void {
    this.runTrackUpdate((): Promise<TrackRecord> => this.selTrackerInst.setRemotePrivate(this.selTrackRec, value));
  }

  private refreshTrack(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.selTrackerInst.refresh(this.selTrackRec)
      .then((remote: TrackRecord): Promise<void> => TrackRepo.upsert(remote))
      .then((): void => {
        this.busy = false;
        this.refreshTracks();
        this.onChanged();
      })
      .catch((): void => {
        this.busy = false;
        Util.toastRes(this.getUIContext(), $r('app.string.track_update_failed'));
      });
  }

  // 解绑选项：0 仅解除本地绑定；1 远端删除 + 本地解除
  private applyRemove(index: number): void {
    if (index === 0) {
      TrackRepo.delete(this.mangaId, this.selTrackerInst.syncId).then((): void => {
        this.mode = MODE_LIST;
        this.refreshTracks();
        this.onChanged();
      }).catch((): void => {
        Util.toastRes(this.getUIContext(), $r('app.string.track_update_failed'));
      });
    } else if (index === 1) {
      if (this.busy) {
        return;
      }
      this.busy = true;
      this.selTrackerInst.deleteRemote(this.selTrackRec)
        .then((): Promise<void> => TrackRepo.delete(this.mangaId, this.selTrackerInst.syncId))
        .then((): void => {
          this.busy = false;
          this.mode = MODE_LIST;
          this.refreshTracks();
          this.onChanged();
        })
        .catch((): void => {
          this.busy = false;
          Util.toastRes(this.getUIContext(), $r('app.string.track_remove_failed'));
        });
    }
  }

  // 追踪行右侧摘要：进度 + 评分
  private trackSummaryText(t: Tracker, track: TrackRecord): string {
    const score = t.displayScore(track);
    const parts: string[] = [];
    if (track.lastChapterRead > 0) {
      parts.push(`${track.lastChapterRead}`);
    }
    if (score !== '' && score !== '-' && score !== '0') {
      parts.push(score);
    }
    return parts.join(' · ');
  }

  private dateText(epochMs: number): string {
    return epochMs > 0 ? Util.formatDate(epochMs) : '-';
  }
}
