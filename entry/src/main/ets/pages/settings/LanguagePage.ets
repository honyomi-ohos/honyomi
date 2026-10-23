import { Settings } from '../../common/Settings';
import { AppLanguage, Languages } from '../../common/Languages';
import { ThemePalette } from '../../common/Theme';
import { NavGlassPage } from '../../common/HdsNavHost';
import { AppIcon } from '../components/AppIcon';

// 语言选择内容：跟随系统 + 各语言自称单选列表（参考 Mihon App language）
@Component
export struct LanguageContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('appLanguage') appLanguage: string = 'auto';

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
    Scroll() {
      Column() {
        this.langRow($r('app.string.lang_follow_system'), 'auto')
        Divider().color(this.pal.divider).margin({ left: 16 })
        ForEach(Languages.all(), (lang: AppLanguage, index: number) => {
          if (index > 0) {
            Divider().color(this.pal.divider).margin({ left: 16 })
          }
          this.langRow(lang.nativeName, lang.tag)
        }, (lang: AppLanguage) => `lang-${lang.tag}`)
      }
      .width('100%')
      .backgroundColor(this.pal.card)
      .borderRadius(16)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .padding({ left: 16, right: 16, top: 4 })
  }

  private select(tag: string): void {
    if (this.appLanguage === tag) {
      return;
    }
    Settings.setAppLanguage(tag);
    Settings.applyAppLanguage();
  }
}

// 语言选择路由壳（手机/平板窄屏 push 进入）
@Component
export struct LanguagePage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavGlassPage({ title: $r('app.string.appearance_language') }) {
      Column() {
        LanguageContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function LanguageBuilder() {
  LanguagePage()
}
