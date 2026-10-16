// 隐私设置（对齐 Mihon SettingsSecurityScreen）：
// 应用锁（系统指纹/人脸/口令认证）/ 切后台时锁定 / 隐藏通知内容 / 隐私界面（防截屏）
// Firebase 遥测开关组不适用（未接入 AGC Analytics/APMS），如后续接入再补
import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { AppLock } from '../../common/AppLock';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, PrefSelectRow, PrefSwitchRow } from '../components/Prefs';

// 空闲锁定档位值（对齐 Mihon LockAfterValues）：0=切后台立即锁 / 1/2/5/10 分钟 / -1=从不
const LOCK_AFTER_VALUES: number[] = [0, 1, 2, 5, 10, -1];
// 隐私界面档位值：始终 / 无痕模式时 / 关闭
const SECURE_VALUES: string[] = ['always', 'incognito', 'never'];

@Component
export struct PrivacyContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State appLock: boolean = false;
  @State authSupported: boolean = true;
  @State lockAfterIdx: number = 0;
  @State secureIdx: number = 1;
  @State hideNotif: boolean = false;

  aboutToAppear(): void {
    this.appLock = Settings.getAppLock();
    this.authSupported = AppLock.isAuthSupported();
    const v: number = Settings.getLockAfterMinutes();
    const idx: number = LOCK_AFTER_VALUES.indexOf(v);
    this.lockAfterIdx = idx >= 0 ? idx : 0;
    const sIdx: number = SECURE_VALUES.indexOf(Settings.getSecureScreen());
    this.secureIdx = sIdx >= 0 ? sIdx : 1;
    this.hideNotif = Settings.getHideNotificationContent();
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.privacy_group') }) {
          PrefSwitchRow({
            icon: 'lock',
            title: $r('app.string.privacy_app_lock'),
            subtitle: this.authSupported ? '' : $r('app.string.privacy_app_lock_no_cred'),
            switchEnabled: this.authSupported,
            initValue: this.appLock,
            apply: (value: boolean): void => {
              this.appLock = value;
              Settings.setAppLock(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 52 })
          PrefSelectRow({
            title: $r('app.string.privacy_lock_after'),
            options: [
              $r('app.string.privacy_lock_after_always'),
              $r('app.string.privacy_lock_after_1min'),
              $r('app.string.privacy_lock_after_2min'),
              $r('app.string.privacy_lock_after_5min'),
              $r('app.string.privacy_lock_after_10min'),
              $r('app.string.privacy_lock_after_never')
            ],
            selectedIndex: this.lockAfterIdx,
            onSelectIndex: (index: number): void => {
              this.lockAfterIdx = index;
              Settings.setLockAfterMinutes(LOCK_AFTER_VALUES[index]);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSwitchRow({
            title: $r('app.string.privacy_hide_notification'),
            initValue: this.hideNotif,
            apply: (value: boolean): void => {
              this.hideNotif = value;
              Settings.setHideNotificationContent(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          PrefSelectRow({
            title: $r('app.string.privacy_secure_screen'),
            options: [
              $r('app.string.privacy_lock_after_always'),
              $r('app.string.more_incognito'),
              $r('app.string.privacy_lock_after_never')
            ],
            selectedIndex: this.secureIdx,
            onSelectIndex: (index: number): void => {
              this.secureIdx = index;
              Settings.setSecureScreen(SECURE_VALUES[index]);
              const ctx = Util.hostAbilityContext(this.getUIContext());
              Settings.applySecureScreen(ctx);
            }
          })
        }

        // 说明文字（对齐 Mihon InfoPreference）
        Text($r('app.string.privacy_secure_summary'))
          .fontSize(13)
          .fontColor(this.pal.sub)
          .width('100%')
          .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }
}

// 隐私设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct PrivacyPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.privacy_title') })
        PrivacyContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function PrivacyBuilder() {
  PrivacyPage()
}
