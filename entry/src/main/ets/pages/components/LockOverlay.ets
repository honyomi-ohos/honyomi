// 应用锁全屏覆盖层：应用图标 + 锁定提示 + 解锁按钮（拉起系统指纹/人脸/口令认证）
// 挂载即自动发起一次系统认证（对齐 Mihon 启动即弹生物认证）；取消后可点按钮再次认证
import { ThemePalette } from '../../common/Theme';
import { AppLock } from '../../common/AppLock';
import { AppKeys } from '../../common/AppKeys';
import { Util } from '../../common/Util';

@Component
export struct LockOverlay {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;

  aboutToAppear(): void {
    // 延迟到首帧稳定后拉起系统认证弹窗，避免与页面挂载争抢
    setTimeout((): void => {
      this.startAuth();
    }, 350);
  }

  build() {
    Column({ space: 16 }) {
      Image($r('app.media.startIcon'))
        .width(84)
        .height(84)
        .borderRadius(20)
      Text($r('app.string.privacy_locked_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.text)
      Text($r('app.string.privacy_locked_summary'))
        .fontSize(14)
        .fontColor(this.pal.sub)
      Button($r('app.string.privacy_unlock_btn'))
        .backgroundColor(this.pal.primary)
        .fontColor(this.pal.onPrimary)
        .padding({
          left: 32,
          right: 32,
          top: 10,
          bottom: 10
        })
        .margin({ top: 8 })
        .onClick(() => {
          this.startAuth();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({
      top: this.statusBarH,
      bottom: this.navBarH,
      left: 32,
      right: 32
    })
    .backgroundColor(this.pal.bg)
  }

  // 发起系统认证；成功后解除锁定态（Index 条件渲染卸载本覆盖层）
  private startAuth(): void {
    const ui = this.getUIContext();
    const title: string = Util.resStr(ui, $r('app.string.privacy_auth_title'));
    AppLock.authenticate(title, (): void => {
      AppStorage.setOrCreate(AppKeys.APP_LOCKED, false);
    });
  }
}
