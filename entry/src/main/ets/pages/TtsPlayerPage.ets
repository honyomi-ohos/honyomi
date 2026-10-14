import { ThemePalette } from '../common/Theme';
import { Bp } from '../common/Breakpoint';
import { Settings } from '../common/Settings';
import { ChapterRecord, MangaRecord } from '../model/Models';
import { TtsPlaybackService, TtsServiceStateHandler, TtsServiceParaHandler, TtsServiceChapterHandler,
  TtsServiceErrorHandler, TtsServiceFinishHandler, TtsServiceSleepHandler } from '../common/TtsPlaybackService';
import { SmartImage } from './components/SmartImage';
import { CoverPlaceholder } from './components/CoverPlaceholder';
import { AppIcon } from './components/AppIcon';

// 语速选项（与阅读器听书面板一致）
const SPEED_OPTIONS: number[] = [0.5, 0.75, 1, 1.25, 1.5, 2];
// 定时停止选项（分钟）
const SLEEP_OPTIONS: number[] = [5, 10, 15, 30, 60];

// 听书播放器页（参考 AudioBook 示例播放器布局）：
// 封面/书名/章节 + 段落进度 + 播放控制（上一章/播放暂停/下一章）+
// 语速、定时停止、章节列表；播放状态由 TtsPlaybackService 全局持有，
// 页面仅订阅展示，离开页面不打断朗读。
@Component
export struct TtsPlayerPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @StorageProp('windowW') windowW: number = 0;
  @State active: boolean = false;
  @State playing: boolean = false;
  @State paraIdx: number = -1;
  @State paraTotal: number = 0;
  @State speed: number = 1;
  @State mangaTitle: string = '';
  @State mangaAuthor: string = '';
  @State coverUrl: string = '';
  @State sourceKey: string = '';
  @State chapterId: number = -1;
  @State chapterName: string = '';
  @State chapters: ChapterRecord[] = [];
  @State sleepRemainingMs: number = -1;
  @State sleepMinutes: number = 0;
  @State showChapters: boolean = false;

  private readonly onState: TtsServiceStateHandler =
    (_playing: boolean, _paused: boolean, _mangaId: number, _chapterId: number): void => {
      this.sync();
    };

  private readonly onPara: TtsServiceParaHandler =
    (_mangaId: number, _chapterId: number, paraIdx: number): void => {
      this.paraIdx = paraIdx;
    };

  private readonly onChapter: TtsServiceChapterHandler = (_mangaId: number, _chapterId: number): void => {
      this.sync();
    };

  private readonly onError: TtsServiceErrorHandler = (_message: string): void => {
      this.sync();
    };

  private readonly onFinish: TtsServiceFinishHandler = (): void => {
      this.sync();
    };

  private readonly onSleep: TtsServiceSleepHandler = (remainingMs: number): void => {
      this.sleepRemainingMs = remainingMs;
      this.sleepMinutes = TtsPlaybackService.sleepTimerMinutes();
    };

  aboutToAppear(): void {
    TtsPlaybackService.events.onState(this.onState);
    TtsPlaybackService.events.onPara(this.onPara);
    TtsPlaybackService.events.onChapter(this.onChapter);
    TtsPlaybackService.events.onError(this.onError);
    TtsPlaybackService.events.onFinish(this.onFinish);
    TtsPlaybackService.events.onSleep(this.onSleep);
    this.sync();
  }

  aboutToDisappear(): void {
    TtsPlaybackService.events.offState(this.onState);
    TtsPlaybackService.events.offPara(this.onPara);
    TtsPlaybackService.events.offChapter(this.onChapter);
    TtsPlaybackService.events.offError(this.onError);
    TtsPlaybackService.events.offFinish(this.onFinish);
    TtsPlaybackService.events.offSleep(this.onSleep);
  }

  // 从全局服务同步播放状态
  private sync(): void {
    this.active = TtsPlaybackService.isActive();
    this.playing = TtsPlaybackService.isPlaying();
    this.paraIdx = TtsPlaybackService.currentParaIdx();
    this.paraTotal = TtsPlaybackService.paraTotal();
    this.speed = Settings.getNovelTtsSpeed();
    this.sleepRemainingMs = -1;
    this.sleepMinutes = TtsPlaybackService.sleepTimerMinutes();
    const m: MangaRecord | undefined = TtsPlaybackService.getManga();
    const ch: ChapterRecord | undefined = TtsPlaybackService.getChapter();
    this.mangaTitle = m !== undefined ? m.title : '';
    this.mangaAuthor = m !== undefined ? m.author : '';
    this.coverUrl = m !== undefined ? m.thumbnailUrl : '';
    this.sourceKey = m !== undefined ? m.sourceKey : '';
    this.chapterId = ch !== undefined ? ch.id : -1;
    this.chapterName = ch !== undefined ? ch.name : '';
    this.chapters = TtsPlaybackService.getChapters();
  }

  // 章节在列表中的位置（-1 未命中）
  private chapterIndex(): number {
    for (let i = 0; i < this.chapters.length; i++) {
      if (this.chapters[i].id === this.chapterId) {
        return i;
      }
    }
    return -1;
  }

  private hasPrev(): boolean {
    return this.chapterIndex() > 0;
  }

  private hasNext(): boolean {
    const idx = this.chapterIndex();
    return idx >= 0 && idx < this.chapters.length - 1;
  }

  // 定时剩余 mm:ss
  private sleepRemainingText(): string {
    const s = Math.ceil(this.sleepRemainingMs / 1000);
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${r < 10 ? `0${r}` : `${r}`}`;
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row({ space: 6 }) {
          Row() {
            AppIcon({ name: 'arrow_back', iconSize: 22 })
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.pathStack.pop();
          })

          Text($r('app.string.tts_player_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.text)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 8, right: 16, top: this.statusBarH + 4 })
        .alignItems(VerticalAlign.Center)

        if (this.active) {
          this.playerBody()
        } else {
          // 无正在朗读的内容
          Column({ space: 12 }) {
            AppIcon({ name: 'playlist_play', iconSize: 44, tint: this.pal.chip })
            Text($r('app.string.tts_no_content'))
              .fontSize(14)
              .fontColor(this.pal.sub)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .bindSheet($$this.showChapters, this.chapterSheetBuilder(), {
      preferType: Bp.isWide(this.windowW) ? SheetType.CENTER : SheetType.BOTTOM,
      width: Bp.isWide(this.windowW) ? 480 : '100%',
      height: SheetSize.LARGE,
      title: { title: $r('app.string.tts_chapters') },
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: true,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      enableOutsideInteractive: true
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

  @Builder
  playerBody() {
    Scroll() {
      Column({ space: 0 }) {
        // 封面（无封面时显示默认封面占位）
        Stack() {
          if (this.coverUrl === '') {
            CoverPlaceholder({ iconSize: 40 })
          } else {
            SmartImage({ url: this.coverUrl, sourceKey: this.sourceKey, fit: ImageFit.Cover, fill: true })
          }
        }
        .width(168)
        .aspectRatio(0.7)
        .borderRadius(12)
        .clip(true)
        .backgroundColor(this.pal.chip)
        .margin({ top: 10 })

        // 书名 / 作者 / 章节
        Text(this.mangaTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.text)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 18 })
        if (this.mangaAuthor !== '') {
          Text(this.mangaAuthor)
            .fontSize(13)
            .fontColor(this.pal.sub)
            .margin({ top: 4 })
        }
        Text(this.chapterName)
          .fontSize(14)
          .fontColor(this.pal.primary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 6, bottom: 4 })

        // 段落进度
        Progress({ value: this.paraIdx + 1, total: this.paraTotal > 0 ? this.paraTotal : 1,
          type: ProgressType.Linear })
          .color(this.pal.primary)
          .margin({ top: 14, bottom: 6 })
          .width(Bp.isWide(this.windowW) ? 360 : '82%')
        Text($r('app.string.tts_para_progress', this.paraIdx + 1, this.paraTotal > 0 ? this.paraTotal : 0))
          .fontSize(12)
          .fontColor(this.pal.sub)

        // 控制区：上一章 / 播放暂停 / 下一章
        Row({ space: 30 }) {
          Row() {
            AppIcon({ name: 'skip_previous', iconSize: 26 })
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.pal.chip)
          .opacity(this.hasPrev() ? 1 : 0.4)
          .onClick(() => {
            TtsPlaybackService.step(-1);
          })

          Row() {
            AppIcon({ name: this.playing ? 'pause' : 'play_arrow', iconSize: 34, tint: '#FFFFFF' })
          }
          .width(72)
          .height(72)
          .borderRadius(36)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.pal.primary)
          .onClick(() => {
            TtsPlaybackService.toggle();
          })

          Row() {
            AppIcon({ name: 'skip_next', iconSize: 26 })
          }
          .width(52)
          .height(52)
          .borderRadius(26)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.pal.chip)
          .opacity(this.hasNext() ? 1 : 0.4)
          .onClick(() => {
            TtsPlaybackService.step(1);
          })
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: 22 })

        // 语速
        this.speedSection()
        // 定时停止
        this.sleepSection()

        // 章节列表入口
        Row({ space: 8 }) {
          AppIcon({ name: 'view_list', iconSize: 20, tint: this.pal.sub })
          Text($r('app.string.tts_chapters'))
            .fontSize(14)
            .fontColor(this.pal.text)
            .layoutWeight(1)
          AppIcon({ name: 'expand_more', iconSize: 20, tint: this.pal.sub })
        }
        .width(Bp.isWide(this.windowW) ? 400 : '88%')
        .padding({ left: 16, right: 16 })
        .height(48)
        .borderRadius(12)
        .backgroundColor(this.pal.card)
        .margin({ top: 20, bottom: 24 })
        .onClick(() => {
          this.showChapters = true;
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Center)
  }

  // 语速选择（0.5x - 2x，切换立即生效）
  @Builder
  speedSection() {
    Column({ space: 8 }) {
      Text($r('app.string.novel_tts_speed'))
        .fontSize(13)
        .fontColor(this.pal.sub)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(SPEED_OPTIONS, (v: number) => {
          Text(`${v}x`)
            .fontSize(13)
            .fontColor(this.speed === v ? '#FFFFFF' : this.pal.text)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(this.speed === v ? this.pal.primary : this.pal.chip)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.speed = v;
              TtsPlaybackService.setSpeed(v);
            })
        }, (v: number) => `${v}`)
      }
      .width('100%')
    }
    .width(Bp.isWide(this.windowW) ? 400 : '88%')
    .margin({ top: 20 })
  }

  // 定时停止（到点暂停，可继续播放）
  @Builder
  sleepSection() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        AppIcon({ name: 'schedule', iconSize: 16, tint: this.pal.sub })
        Text($r('app.string.tts_sleep_timer'))
          .fontSize(13)
          .fontColor(this.pal.sub)
        if (this.sleepRemainingMs > 0) {
          Text($r('app.string.tts_sleep_stop_after', this.sleepRemainingText()))
            .fontSize(13)
            .fontColor(this.pal.primary)
        }
      }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        // 关闭
        Text($r('app.string.tts_sleep_off'))
          .fontSize(13)
          .fontColor(this.sleepMinutes === 0 ? '#FFFFFF' : this.pal.text)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.sleepMinutes === 0 ? this.pal.primary : this.pal.chip)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.sleepMinutes = 0;
            TtsPlaybackService.setSleepTimer(0);
          })
        ForEach(SLEEP_OPTIONS, (v: number) => {
          Text($r('app.string.tts_sleep_minutes', v))
            .fontSize(13)
            .fontColor(this.sleepMinutes === v ? '#FFFFFF' : this.pal.text)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(this.sleepMinutes === v ? this.pal.primary : this.pal.chip)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.sleepMinutes = v;
              TtsPlaybackService.setSleepTimer(v);
            })
        }, (v: number) => `${v}`)
      }
      .width('100%')
    }
    .width(Bp.isWide(this.windowW) ? 400 : '88%')
    .margin({ top: 16 })
  }

  // 章节列表面板
  @Builder
  chapterSheetBuilder() {
    Column() {
      if (this.chapters.length === 0) {
        Column() {
          Text($r('app.string.tts_no_content'))
            .fontSize(14)
            .fontColor(this.pal.sub)
        }
        .width('100%')
        .padding({ top: 32, bottom: 32 })
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.chapters, (ch: ChapterRecord) => {
            ListItem() {
              Row({ space: 10 }) {
                Text(ch.name)
                  .fontSize(14)
                  .fontColor(ch.id === this.chapterId ? this.pal.primary :
                    (ch.read ? this.pal.sub : this.pal.text))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (ch.id === this.chapterId) {
                  AppIcon({ name: 'play_arrow', iconSize: 18, tint: this.pal.primary })
                }
              }
              .width('100%')
              .height(48)
              .padding({ left: 20, right: 20 })
              .onClick(() => {
                this.showChapters = false;
                if (ch.id !== this.chapterId) {
                  TtsPlaybackService.selectChapter(ch.id);
                }
              })
            }
          }, (ch: ChapterRecord) => `${ch.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: this.pal.divider, startMargin: 20, endMargin: 20 })
      }
    }
    .width('100%')
    .height('100%')
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function TtsPlayerBuilder() {
  TtsPlayerPage()
}
