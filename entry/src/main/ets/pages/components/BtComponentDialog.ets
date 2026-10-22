/*
 * BtComponentDialog — BT 组件（torrent HSP）按需安装引导覆盖层。
 *
 * DownloadService 捕获 bt_component_required 后置 AppStorage 'btComponentAsk'，
 * Index 条件挂载本组件。三阶段：ask（询问下载）→ downloading（进度）→
 * failed（重试/关闭）。安装成功后自动重跑因组件缺失失败的任务。
 */
import { ThemePalette } from '../../common/Theme';
import { AppKeys } from '../../common/AppKeys';
import { BtComponentInstaller } from '../../common/BtComponentInstaller';
import { DownloadService } from '../../data/DownloadService';

// 组件下载体量提示（MB，约值：arm64 libtorrent release HSP 实测 9.8MB）
const BT_COMPONENT_SIZE_MB = 10;

@Component
export struct BtComponentDialog {
  @StorageLink('btComponentAsk') ask: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 0=询问下载 1=下载安装中 2=失败
  @State phase: number = 0;
  @State progress: number = 0;

  build() {
    Stack() {
      // 遮罩（非失败/询问阶段点击不关闭，避免误触中断安装）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          if (this.phase === 0) {
            this.decline();
          }
        })
      Column({ space: 16 }) {
        if (this.phase === 0) {
          Text($r('app.string.download_bt_component_required'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
          Text($r('app.string.bt_component_ask_msg', BT_COMPONENT_SIZE_MB))
            .fontSize(14)
            .fontColor(this.pal.sub)
            .textAlign(TextAlign.Center)
          Row({ space: 12 }) {
            Button($r('app.string.common_cancel'))
              .layoutWeight(1)
              .backgroundColor(this.pal.chip)
              .fontColor(this.pal.text)
              .onClick(() => {
                this.decline();
              })
            Button($r('app.string.action_download'))
              .layoutWeight(1)
              .backgroundColor(this.pal.primary)
              .fontColor(this.pal.onPrimary)
              .onClick(() => {
                this.startInstall();
              })
          }
          .width('100%')
        } else if (this.phase === 1) {
          Text($r('app.string.bt_component_downloading'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.pal.primary)
          Text(`${this.progress}%`)
            .fontSize(13)
            .fontColor(this.pal.sub)
          Button($r('app.string.common_cancel'))
            .backgroundColor(this.pal.chip)
            .fontColor(this.pal.text)
            .onClick(() => {
              BtComponentInstaller.cancelCurrent();
              this.decline();
            })
        } else {
          Text($r('app.string.bt_component_download_failed'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .textAlign(TextAlign.Center)
          Row({ space: 12 }) {
            Button($r('app.string.common_cancel'))
              .layoutWeight(1)
              .backgroundColor(this.pal.chip)
              .fontColor(this.pal.text)
              .onClick(() => {
                this.decline();
              })
            Button($r('app.string.common_retry'))
              .layoutWeight(1)
              .backgroundColor(this.pal.primary)
              .fontColor(this.pal.onPrimary)
              .onClick(() => {
                this.startInstall();
              })
          }
          .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Center)
      .padding(24)
      .width('86%')
      .borderRadius(20)
      .backgroundColor(this.pal.card)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  // 用户拒绝：置 dismissed 抑制后续自动弹窗（手动重试会重新武装）
  private decline(): void {
    AppStorage.setOrCreate(AppKeys.BT_ASK_DISMISSED, true);
    this.ask = false;
    this.phase = 0;
    this.progress = 0;
  }

  // 发起按需安装；成功后关闭弹窗并重跑因组件缺失失败的任务
  private startInstall(): void {
    const context = DownloadService.abilityContext();
    if (context === undefined) {
      this.phase = 2;
      return;
    }
    this.phase = 1;
    this.progress = 0;
    BtComponentInstaller.requestInstall(context, (progress: number): void => {
      this.progress = progress;
    })
      .then((): void => {
        this.ask = false;
        this.phase = 0;
        this.progress = 0;
        DownloadService.retryBtComponentTasks();
      })
      .catch((): void => {
        this.phase = 2;
      });
  }
}
