import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { CookieJar } from '../../net/CookieJar';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup, TextRow, IconRow } from '../components/Prefs';
import { OnboardingParams } from '../../model/RouteParams';

// 高级设置内容：新手引导 / Cookie（备份、章节缓存清理已移至「数据与存储」，追踪已移至「追踪」页）
@Component
export struct AdvancedContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 打开新手引导（由宿主注入导航；lg 双栏与窄屏壳均 push Onboarding 路由）
  onOpenOnboarding: () => void = () => {};

  build() {
    Scroll() {
      Column() {
        PrefGroup() {
          IconRow({
            title: $r('app.string.pref_onboarding_guide'),
            icon: 'rocket_launch',
            onTap: (): void => {
              this.onOpenOnboarding();
            }
          })
        }

        PrefGroup() {
          TextRow({
            title: $r('app.string.advanced_clear_cookies'),
            onTap: (): void => {
              CookieJar.clear();
              Util.toastRes(this.getUIContext(), $r('app.string.advanced_cookies_cleared'));
            }
          })
        }
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

// 高级设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct AdvancedPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Consume('navStack') pathStack: NavPathStack;

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.advanced_title') })
        AdvancedContent({
          onOpenOnboarding: (): void => {
            const params: OnboardingParams = { firstRun: false };
            this.pathStack.pushPathByName('Onboarding', params);
          }
        })
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
export function AdvancedBuilder() {
  AdvancedPage()
}
