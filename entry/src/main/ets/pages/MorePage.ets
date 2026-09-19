import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { CategoryRepo } from '../data/Repos';
import { CategoryRecord } from '../model/Models';
import { Theme } from '../common/Theme';
import { Util } from '../common/Util';
import { Settings } from '../common/Settings';
import { InputDialog } from './components/Dialogs';

// 更多页：外观 / 阅读设置 / 分类管理 / 关于
@Component
export struct MorePage {
  @StorageProp('isDark') isDark: boolean = false;
  @State themeMode: string = 'auto';
  @State readerMode: string = 'ltr';
  @State categories: CategoryRecord[] = [];

  aboutToAppear(): void {
    this.themeMode = Settings.getThemeMode();
    this.readerMode = Settings.getReaderMode();
    this.loadCategories();
  }

  async loadCategories(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await AppDb.ready(context);
    this.categories = await CategoryRepo.list();
  }

  private applyTheme(mode: string): void {
    this.themeMode = mode;
    Settings.setThemeMode(mode);
    const systemDark = AppStorage.get<boolean>('isDarkSystem') ?? false;
    Settings.applyTheme(systemDark);
  }

  private applyReaderMode(mode: string): void {
    this.readerMode = mode;
    Settings.setReaderMode(mode);
  }

  private showAddCategory(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: '新建分类',
        placeholder: '分类名称',
        onConfirm: (text: string): void => {
          if (text.trim() !== '') {
            CategoryRepo.add(text.trim()).then(() => {
              this.loadCategories();
            });
          }
        },
      }),
      autoCancel: true,
    });
    dialog.open();
  }

  build() {
    Column() {
      Text('更多')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.text(this.isDark))
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column() {
          // 外观
          Column() {
            Text('外观')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text(this.isDark))
              .width('100%')
              .margin({ bottom: 10 })
            Row({ space: 8 }) {
              Text('跟随系统')
                .fontSize(13)
                .fontColor(this.themeMode === 'auto' ? '#FFFFFF' : Theme.text(this.isDark))
                .backgroundColor(this.themeMode === 'auto' ? Theme.primary(this.isDark) : Theme.chip(this.isDark))
                .borderRadius(14)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.applyTheme('auto');
                })
              Text('浅色')
                .fontSize(13)
                .fontColor(this.themeMode === 'light' ? '#FFFFFF' : Theme.text(this.isDark))
                .backgroundColor(this.themeMode === 'light' ? Theme.primary(this.isDark) : Theme.chip(this.isDark))
                .borderRadius(14)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.applyTheme('light');
                })
              Text('深色')
                .fontSize(13)
                .fontColor(this.themeMode === 'dark' ? '#FFFFFF' : Theme.text(this.isDark))
                .backgroundColor(this.themeMode === 'dark' ? Theme.primary(this.isDark) : Theme.chip(this.isDark))
                .borderRadius(14)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.applyTheme('dark');
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.card(this.isDark))
          .borderRadius(14)
          .margin({ left: 16, right: 16, top: 4 })

          // 阅读设置
          Column() {
            Text('默认阅读模式')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text(this.isDark))
              .width('100%')
              .margin({ bottom: 10 })
            Row({ space: 8 }) {
              Text('左右翻页')
                .fontSize(13)
                .fontColor(this.readerMode === 'ltr' ? '#FFFFFF' : Theme.text(this.isDark))
                .backgroundColor(this.readerMode === 'ltr' ? Theme.primary(this.isDark) : Theme.chip(this.isDark))
                .borderRadius(14)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.applyReaderMode('ltr');
                })
              Text('右→左')
                .fontSize(13)
                .fontColor(this.readerMode === 'rtl' ? '#FFFFFF' : Theme.text(this.isDark))
                .backgroundColor(this.readerMode === 'rtl' ? Theme.primary(this.isDark) : Theme.chip(this.isDark))
                .borderRadius(14)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.applyReaderMode('rtl');
                })
              Text('条漫')
                .fontSize(13)
                .fontColor(this.readerMode === 'webtoon' ? '#FFFFFF' : Theme.text(this.isDark))
                .backgroundColor(this.readerMode === 'webtoon' ? Theme.primary(this.isDark) : Theme.chip(this.isDark))
                .borderRadius(14)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.applyReaderMode('webtoon');
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Theme.card(this.isDark))
          .borderRadius(14)
          .margin({ left: 16, right: 16, top: 12 })

          // 分类管理
          Column() {
            Row() {
              Text('分类管理')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.text(this.isDark))
                .layoutWeight(1)
              Text('＋ 新建')
                .fontSize(13)
                .fontColor(Theme.primary(this.isDark))
                .onClick(() => {
                  this.showAddCategory();
                })
            }
            .width('100%')
            .margin({ bottom: 8 })

            ForEach(this.categories, (cat: CategoryRecord) => {
              Row() {
                Text(cat.name)
                  .fontSize(14)
                  .fontColor(Theme.text(this.isDark))
                  .layoutWeight(1)
                if (cat.id !== 1) {
                  Text('删除')
                    .fontSize(13)
                    .fontColor('#E05252')
                    .onClick(() => {
                      CategoryRepo.remove(cat.id).then(() => {
                        this.loadCategories();
                        AppStorage.set('libDirty', (AppStorage.get<number>('libDirty') ?? 0) + 1);
                      });
                    })
                }
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
            }, (cat: CategoryRecord) => `more-cat-${cat.id}`)

            Text('删除分类后，该分类下的漫画会移回「默认」分类')
              .fontSize(11)
              .fontColor(Theme.sub(this.isDark))
              .margin({ top: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(Theme.card(this.isDark))
          .borderRadius(14)
          .margin({ left: 16, right: 16, top: 12 })

          // 关于
          Column() {
            Text('关于')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text(this.isDark))
              .width('100%')
              .margin({ bottom: 8 })
            Text('MihonHarmony P1 · 鸿蒙漫画阅读器')
              .fontSize(13)
              .fontColor(Theme.sub(this.isDark))
            Text('架构参考 Mihon (Apache-2.0)，数据源：MangaDex API / 本地文件')
              .fontSize(12)
              .fontColor(Theme.sub(this.isDark))
              .margin({ top: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .backgroundColor(Theme.card(this.isDark))
          .borderRadius(14)
          .margin({ left: 16, right: 16, top: 12, bottom: 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bg(this.isDark))
  }
}
