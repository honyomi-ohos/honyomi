import { ThemePalette } from '../../common/Theme';
import { PageHeader } from '../components/PageHeader';

// 关于页：logo + 版本 + 开源致谢
@Component
export struct AboutPage {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.about_title') })
        Scroll() {
          Column() {
            Image($r('app.media.startIcon'))
              .width(96)
              .height(96)
              .borderRadius(20)
              .margin({ top: 32 })
            Text('MihonHarmony')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.text)
              .margin({ top: 12 })
            Text($r('app.string.about_version'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .margin({ top: 4 })

            Column() {
              Text($r('app.string.about_desc'))
                .fontSize(13)
                .fontColor(this.pal.text)
                .lineHeight(20)
              Text($r('app.string.about_ack'))
                .fontSize(12)
                .fontColor(this.pal.sub)
                .lineHeight(19)
                .margin({ top: 10 })
            }
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .backgroundColor(this.pal.card)
            .borderRadius(16)
            .margin({ left: 16, right: 16, top: 24 })
          }
          .width('100%')
          .padding({ bottom: 24 })
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
  }
}
