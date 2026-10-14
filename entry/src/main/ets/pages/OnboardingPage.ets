// 新手引导页（对齐 Mihon OnboardingScreen / InfoScreen）：
// 步骤 1 主题（模式/主题色/AMOLED）→ 步骤 2 指南（入门指南/还原备份）；
// 首启未完成引导时拦截返回（Mihon BackHandler 行为），完成后落库 shownOnboarding。
// 注：Mihon 的存储选择/权限步骤为 Android SAF 与安装权限场景，鸿蒙沙箱存储下不适用，故省略。
import { ThemePalette, Theme } from '../common/Theme';
import { Settings } from '../common/Settings';
import { Util } from '../common/Util';
import { BackupService } from '../data/BackupService';
import { OnboardingParams } from '../model/RouteParams';
import { AppIcon } from './components/AppIcon';

const GETTING_STARTED_URL: string = 'https://mihon.app/docs/guides/getting-started';
const APP_NAME: string = 'Honyomi';

// 步骤 1：主题（复用外观设置的主题模式/主题色/AMOLED 逻辑）
@Component
struct OnboardingThemeStep {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('accent') accent: string = 'blue';
  @State themeMode: string = 'auto';
  @State amoled: boolean = false;

  aboutToAppear(): void {
    this.themeMode = Settings.getThemeMode();
    this.amoled = Settings.getAmoledMode();
  }

  private applyTheme(mode: string): void {
    this.themeMode = mode;
    Settings.setThemeMode(mode);
    const systemDark = AppStorage.get<boolean>('isDarkSystem') ?? false;
    Settings.applyTheme(systemDark);
    Settings.applyColorMode(Util.hostAbilityContext(this.getUIContext()));
  }

  @Builder
  modeChip(label: Resource | string, mode: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.themeMode === mode ? '#FFFFFF' : this.pal.text)
      .backgroundColor(this.themeMode === mode ? this.pal.primary : this.pal.chip)
      .borderRadius(16)
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .onClick(() => {
        this.applyTheme(mode);
      })
  }

  build() {
    Column() {
      // 主题模式
      Row({ space: 8 }) {
        this.modeChip($r('app.string.appearance_theme_auto'), 'auto')
        this.modeChip($r('app.string.appearance_theme_light'), 'light')
        this.modeChip($r('app.string.appearance_theme_dark'), 'dark')
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })

      Divider().color(this.pal.divider)

      // 主题色
      Row({ space: 18 }) {
        ForEach(Theme.accentNames(), (name: string) => {
          Column({ space: 4 }) {
            Column() {
              if (this.accent === name) {
                Column()
                  .width(12)
                  .height(12)
                  .borderRadius(6)
                  .backgroundColor('#FFFFFF')
              }
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(Theme.accentDot(name))
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .border({
              width: this.accent === name ? 2 : 0,
              color: this.pal.text
            })
            .onClick(() => {
              this.accent = name;
              Settings.setAccentColor(name);
              Settings.applyAccent();
            })
            Text(Theme.accentLabel(name))
              .fontSize(11)
              .fontColor(this.pal.sub)
          }
          .alignItems(HorizontalAlign.Center)
        }, (name: string) => `accent-${name}`)
      }
      .width('100%')
      .padding({ top: 16, bottom: 16 })

      Divider().color(this.pal.divider)

      // AMOLED 纯黑背景
      Row() {
        Text($r('app.string.appearance_amoled'))
          .fontSize(15)
          .fontColor(this.pal.text)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.amoled })
          .selectedColor(this.pal.primary)
          .onChange((value: boolean) => {
            this.amoled = value;
            Settings.setAmoledMode(value);
            Settings.applyAccent();
          })
      }
      .width('100%')
      .padding({ top: 14, bottom: 16 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

// 步骤 2：指南（新用户入门指南 / 老用户还原备份，对齐 Mihon GuidesStep）
@Component
struct OnboardingGuidesStep {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State newUserText: string = '';
  @State returningUserText: string = '';
  onOpenGuide: () => void = () => {};
  onRestoreBackup: () => void = () => {};

  aboutToAppear(): void {
    this.newUserText =
      Util.resStr(this.getUIContext(), $r('app.string.onboarding_guides_new_user'), [APP_NAME]);
    this.returningUserText =
      Util.resStr(this.getUIContext(), $r('app.string.onboarding_guides_returning_user'), [APP_NAME]);
  }

  build() {
    Column({ space: 12 }) {
      Text(this.newUserText)
        .fontSize(14)
        .fontColor(this.pal.sub)
        .lineHeight(21)
      Button($r('app.string.getting_started_guide'))
        .width('100%')
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.pal.primary)
        .fontColor('#FFFFFF')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          this.onOpenGuide();
        })

      Divider()
        .color(this.pal.divider)
        .margin({ top: 8, bottom: 8 })

      Text(this.returningUserText)
        .fontSize(14)
        .fontColor(this.pal.sub)
        .lineHeight(21)
      Button($r('app.string.data_restore_backup'))
        .width('100%')
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.pal.chip)
        .fontColor(this.pal.text)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          this.onRestoreBackup();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 16, bottom: 16 })
  }
}

// 引导页主体（InfoScreen 布局：图标 + 标题 + 副标题 + 步骤内容 + 底部主按钮）
@Component
export struct OnboardingPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State currentStep: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  private firstRun: boolean = false;

  private readonly stepCount: number = 2;

  private isLastStep(): boolean {
    return this.currentStep === this.stepCount - 1;
  }

  // 完成引导：落库 + 返回上一页
  private finish(): void {
    Settings.setShownOnboarding(true);
    this.pathStack.pop();
  }

  private goStep(target: number): void {
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Friction }, (): void => {
      this.currentStep = target;
    });
  }

  private onAccept(): void {
    if (this.isLastStep()) {
      this.finish();
      return;
    }
    this.goStep(this.currentStep + 1);
  }

  private openGuide(): void {
    const context = Util.hostAbilityContext(this.getUIContext());
    Util.openUrl(context, GETTING_STARTED_URL);
  }

  // 还原备份（复用 BackupService；成功后视同完成引导，对齐 Mihon onRestoreBackup 行为）
  private async doRestoreBackup(): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      const count = await BackupService.importBackup(context);
      if (count === -1) {
        // 用户取消选择
        return;
      }
      if (count === -2) {
        Util.toastRes(this.getUIContext(), $r('app.string.advanced_backup_invalid'));
        return;
      }
      Util.toastRes(this.getUIContext(), $r('app.string.advanced_restored_manga'), [count]);
      AppStorage.setOrCreate('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
      this.finish();
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.advanced_import_failed'));
    }
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            // 图标 + 标题 + 副标题
            AppIcon({
              name: 'rocket_launch',
              iconSize: 48,
              tint: this.pal.primary
            })
            Text($r('app.string.onboarding_heading'))
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pal.text)
              .margin({ top: 12 })
            Text($r('app.string.onboarding_description'))
              .fontSize(14)
              .fontColor(this.pal.sub)
              .lineHeight(21)
              .margin({ top: 8 })
              .constraintSize({ maxWidth: 560 })

            // 步骤内容卡片
            Column() {
              if (this.currentStep === 0) {
                OnboardingThemeStep()
                  .transition(TransitionEffect.asymmetric(
                    TransitionEffect.OPACITY
                      .combine(TransitionEffect.translate({ x: 48 }))
                      .animation({ duration: 250, curve: Curve.Friction }),
                    TransitionEffect.OPACITY
                      .combine(TransitionEffect.translate({ x: -48 }))
                      .animation({ duration: 250, curve: Curve.Friction })
                  ))
              } else {
                OnboardingGuidesStep({
                  onOpenGuide: (): void => {
                    this.openGuide();
                  },
                  onRestoreBackup: (): void => {
                    this.doRestoreBackup();
                  }
                })
                  .transition(TransitionEffect.asymmetric(
                    TransitionEffect.OPACITY
                      .combine(TransitionEffect.translate({ x: 48 }))
                      .animation({ duration: 250, curve: Curve.Friction }),
                    TransitionEffect.OPACITY
                      .combine(TransitionEffect.translate({ x: -48 }))
                      .animation({ duration: 250, curve: Curve.Friction })
                  ))
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: 560 })
            .borderRadius(16)
            .backgroundColor(this.pal.card)
            .clip(true)
            .padding({ left: 16, right: 16 })
            .margin({ top: 20 })
          }
          .width('100%')
          .padding({
            left: 24,
            right: 24,
            top: this.statusBarH + 24,
            bottom: 24
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .width('100%')

        // 底部操作栏：下一步 / 开始使用
        Column() {
          Divider().color(this.pal.divider)
          Button(this.isLastStep() ?
            $r('app.string.onboarding_action_finish') :
            $r('app.string.onboarding_action_next'))
            .width('100%')
            .height(48)
            .borderRadius(24)
            .backgroundColor(this.pal.primary)
            .fontColor('#FFFFFF')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 12 })
            .onClick(() => {
              this.onAccept();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: this.navBarH + 12 })
        .backgroundColor(this.pal.bg)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onBackPressed(() => {
      // 步骤间返回上一步；首启未完成时拦截返回防止跳过（对齐 Mihon BackHandler）
      if (this.currentStep > 0) {
        this.goStep(this.currentStep - 1);
        return true;
      }
      if (this.firstRun && !Settings.getShownOnboarding()) {
        return true;
      }
      return false;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as OnboardingParams;
      this.firstRun = params !== undefined && params !== null ? params.firstRun : false;
    })
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function OnboardingBuilder() {
  OnboardingPage()
}
