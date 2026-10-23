// 追踪设置页（对齐 Mihon SettingsTrackingScreen）：
// - 8 个追踪器登录/登出（OAuth WebView / 账密弹窗，与 TrackSheet 流程一致）
// - 阅读进度自动同步开关
import { ThemePalette } from '../../common/Theme';
import { Bp } from '../../common/Breakpoint';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { Tracker } from '../../data/track/Tracker';
import { TrackerManager } from '../../data/track/TrackerManager';
import { NavGlassPage } from '../../common/HdsNavHost';
import { PrefGroup, SwitchRow } from '../components/Prefs';
import { TrackLogo } from '../components/TrackLogo';
import { OAuthSheet } from '../components/OAuthSheet';
import { ConfirmDialog, CredentialsDialog } from '../components/Dialogs';
import { AppIcon } from '../components/AppIcon';

// 追踪设置内容
@Component
export struct TrackingContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  // 登录态变化计数：驱动行刷新（登录态读取自 Settings，非响应式）
  @State loginTick: number = 0;
  @State autoUpdate: boolean = true;
  @State busy: boolean = false;
  // OAuth 授权弹层
  @State showOAuth: boolean = false;
  @State oauthUrl: string = '';
  @State oauthTitle: string = '';
  private oauthSyncId: number = 0;

  aboutToAppear(): void {
    this.autoUpdate = Settings.getTrackAutoUpdate();
  }

  // ----- 登录 -----

  @Builder
  trackerRow(t: Tracker) {
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
        if (t.isLoggedIn()) {
          Text(t.getDisplayUsername())
            .fontSize(12)
            .fontColor(this.pal.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (t.isLoggedIn()) {
        Text($r('app.string.track_logout'))
          .fontSize(13)
          .fontColor(this.pal.sub)
      } else if (this.busy) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.pal.primary)
      } else {
        Text($r('app.string.track_login'))
          .fontSize(13)
          .fontColor(this.pal.primary)
      }
      AppIcon({ name: 'keyboard_arrow_right', iconSize: 20, tint: this.pal.sub })
        .margin({ left: 4 })
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
    Scroll() {
      Column({ space: 12 }) {
        // 阅读进度自动同步（对齐 Mihon autoUpdateTrackers 开关）
        PrefGroup() {
          SwitchRow({
            title: $r('app.string.track_auto_update'),
            isOn: this.autoUpdate,
            onChange: (value: boolean): void => {
              this.autoUpdate = value;
              Settings.setTrackAutoUpdate(value);
            }
          })
        }

        // 追踪器列表
        PrefGroup() {
          ForEach(TrackerManager.trackers, (t: Tracker, index: number) => {
            if (index > 0) {
              Divider().color(this.pal.divider).margin({ left: 16 })
            }
            this.trackerRow(t)
          }, (t: Tracker): string => `trk-${t.syncId}-${this.loginTick}`)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
    .bindSheet($$this.showOAuth, this.oauthBuilder(), {
      height: '80%',
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
      width: Bp.isWide(this.windowW) ? 560 : '100%',
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      maskColor: 'rgba(0,0,0,0.45)'
    })
  }

  private startLogin(t: Tracker): void {
    if (this.busy) {
      return;
    }
    // 账密登录型：Kitsu / MangaUpdates
    if (t.syncId === TrackerManager.kitsu.syncId || t.syncId === TrackerManager.mangaUpdates.syncId) {
      this.showCredentialsLogin(t);
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

  // ----- 登出 -----

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
      Util.toastRes(this.getUIContext(), $r('app.string.track_logged_in'), [t.name]);
    }).catch((): void => {
      this.busy = false;
      Util.toastRes(this.getUIContext(), $r('app.string.track_login_failed'));
    });
  }

  private confirmLogout(t: Tracker): void {
    const dialog = new CustomDialogController({
      builder: ConfirmDialog({
        title: $r('app.string.track_logout'),
        message: Util.resStr(this.getUIContext(), $r('app.string.track_logout_confirm'), [t.name]),
        onConfirm: (): void => {
          t.logout();
          this.loginTick += 1;
          Util.toastRes(this.getUIContext(), $r('app.string.track_logged_out'));
          dialog.close();
        },
        onClose: (): void => {
          dialog.close();
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  private onTrackerTap(t: Tracker): void {
    if (t.isLoggedIn()) {
      this.confirmLogout(t);
    } else {
      this.startLogin(t);
    }
  }
}

// 追踪设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct TrackingPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavGlassPage({ title: $r('app.string.track_title') }) {
      Column() {
        TrackingContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function TrackingBuilder() {
  TrackingPage()
}
