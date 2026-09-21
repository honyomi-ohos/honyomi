import { Settings } from '../../common/Settings';
import { Languages, AppLanguage } from '../../common/Languages';
import { ThemePalette } from '../../common/Theme';
import { PageHeader } from '../components/PageHeader';
import { AppIcon } from '../components/AppIcon';

// 语言选择页：跟随系统 + 各语言自称单选列表（参考 Mihon App language）
@Component
export struct LanguagePage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('appLanguage') appLanguage: string = 'auto';

  private select(tag: string): void {
    if (this.appLanguage === tag) {
      return;
    }
    Settings.setAppLanguage(tag);
    Settings.applyAppLanguage();
  }

  @Builder
  langRow(label: Resource | string, tag: string) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
      if (this.appLanguage === tag) {
        AppIcon({ name: 'check_circle', iconSize: 22 })
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      this.select(tag);
    })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.appearance_language') })
        Scroll() {
          Column() {
            this.langRow($r('app.string.lang_follow_system'), 'auto')
            ForEach(Languages.all(), (lang: AppLanguage) => {
              this.langRow(lang.nativeName, lang.tag)
            }, (lang: AppLanguage) => `lang-${lang.tag}`)
          }
          .width('100%')
          .backgroundColor(this.pal.card)
          .borderRadius(16)
          .clip(true)
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, top: 4 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}
