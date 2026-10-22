/*
 * BtEngineChoiceDialog — BT 下载方式选择弹窗（内置引擎 / 系统应用）。
 *
 * BtFlow.acquireEngineChoice 在首次 BT 下载时经 ComponentContent + wrapBuilder
 * + openCustomDialog 弹出本组件（不依赖页面上下文）。选择结果经回调回传
 * BtFlow 持久化（Settings.btEngineChoice）。
 */
import { ThemePalette } from '../../common/Theme';

// 内置引擎组件体量提示（MB，约值：arm64 libtorrent release HSP 实测 9.8MB；与 BtComponentDialog 保持一致）
const BT_ENGINE_SIZE_MB = 10;

// wrapBuilder 入参（@Builder 形参必须为显式 class）
export class BtEngineChoiceParams {
  onPick: (choice: string) => void = (_choice: string) => {
  };
  onCancel: () => void = () => {
  };
}

// ComponentContent 使用的全局 @Builder（wrapBuilder 封装后传入）
@Builder
export function BtEngineChoiceBuilder(params: BtEngineChoiceParams) {
  BtEngineChoiceContent({
    onPick: params.onPick,
    onCancel: params.onCancel
  })
}

@Component
struct BtEngineChoiceContent {
  onPick: (choice: string) => void = (_choice: string) => {
  };
  onCancel: () => void = () => {
  };
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    Column({ space: 14 }) {
      Column({ space: 6 }) {
        Text($r('app.string.bt_choice_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
        Text($r('app.string.bt_choice_msg'))
          .fontSize(14)
          .fontColor(this.pal.sub)
          .textAlign(TextAlign.Center)
      }

      // 内置引擎选项卡（组件体量以 $r 参数格式化，确保 %1$d 正确替换）
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text($r('app.string.bt_choice_module'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.text)
          Text($r('app.string.bt_choice_size_mb', BT_ENGINE_SIZE_MB))
            .fontSize(11)
            .fontColor(this.pal.primary)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor(this.pal.card)
        }
        Text($r('app.string.bt_choice_module_desc'))
          .fontSize(12)
          .fontColor(this.pal.sub)
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(12)
      .backgroundColor(this.pal.chip)
      .width('100%')
      .onClick(() => {
        this.onPick('module');
      })

      // 系统应用选项卡
      Column({ space: 4 }) {
        Text($r('app.string.bt_choice_system'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.text)
        Text($r('app.string.bt_choice_system_desc'))
          .fontSize(12)
          .fontColor(this.pal.sub)
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(12)
      .backgroundColor(this.pal.chip)
      .width('100%')
      .onClick(() => {
        this.onPick('system');
      })

      Text($r('app.string.bt_choice_hint'))
        .fontSize(12)
        .fontColor(this.pal.sub)
        .textAlign(TextAlign.Center)

      Button($r('app.string.common_cancel'))
        .width('100%')
        .backgroundColor(Color.Transparent)
        .fontColor(this.pal.sub)
        .onClick(() => {
          this.onCancel();
        })
    }
    .padding(22)
    .width(320)
    .borderRadius(20)
    .backgroundColor(this.pal.card)
  }
}
