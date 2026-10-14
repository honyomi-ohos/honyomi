import { ThemePalette } from '../../../common/Theme';
import { ChapterRecord, MangaRecord } from '../../../model/Models';
import { TtsPlaybackService, TtsServiceStateHandler, TtsServiceChapterHandler } from '../../../common/TtsPlaybackService';
import { AppIcon } from '../AppIcon';

// 首页听书迷你条：听书进行中（播放/暂停）时悬浮于底部页签上方，
// 显示当前章节，点击进入听书播放器；支持 播放/暂停 与 停止。
@Component
export struct TtsMiniBar {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop navBarH: number = 0;
  @Consume('navStack') pathStack: NavPathStack;
  @State active: boolean = false;
  @State playing: boolean = false;
  @State chapterName: string = '';
  @State mangaTitle: string = '';

  private readonly onState: TtsServiceStateHandler =
    (_playing: boolean, _paused: boolean, _mangaId: number, _chapterId: number): void => {
      this.sync();
    };

  private readonly onChapter: TtsServiceChapterHandler = (_mangaId: number, _chapterId: number): void => {
      this.sync();
    };

  aboutToAppear(): void {
    TtsPlaybackService.events.onState(this.onState);
    TtsPlaybackService.events.onChapter(this.onChapter);
    this.sync();
  }

  aboutToDisappear(): void {
    TtsPlaybackService.events.offState(this.onState);
    TtsPlaybackService.events.offChapter(this.onChapter);
  }

  private sync(): void {
    this.active = TtsPlaybackService.isActive();
    this.playing = TtsPlaybackService.isPlaying();
    const m: MangaRecord | undefined = TtsPlaybackService.getManga();
    const ch: ChapterRecord | undefined = TtsPlaybackService.getChapter();
    this.mangaTitle = m !== undefined ? m.title : '';
    this.chapterName = ch !== undefined ? ch.name : '';
  }

  build() {
    if (this.active) {
      Row({ space: 8 }) {
        AppIcon({ name: 'playlist_play', iconSize: 20, tint: this.pal.primary })
        Column({ space: 2 }) {
          Text(this.chapterName)
            .fontSize(13)
            .fontColor(this.pal.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.mangaTitle)
            .fontSize(11)
            .fontColor(this.pal.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 播放/暂停
        Row() {
          AppIcon({ name: this.playing ? 'pause' : 'play_arrow', iconSize: 22 })
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.pal.chip)
        .onClick(() => {
          TtsPlaybackService.toggle();
        })

        // 停止
        Row() {
          AppIcon({ name: 'close', iconSize: 16, tint: this.pal.sub })
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.pal.chip)
        .onClick(() => {
          TtsPlaybackService.stop();
        })
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 14, right: 8, top: 6, bottom: 6 })
      .borderRadius(24)
      .backgroundColor(this.pal.card)
      .shadow({ radius: 16, color: '#33000000', offsetY: 4 })
      .margin({ left: 12, right: 12, bottom: this.navBarH + 76 })
      .onClick(() => {
        this.pathStack.pushPathByName('TtsPlayer', null);
      })
    } else {
      Column()
        .width(0)
        .height(0)
        .hitTestBehavior(HitTestMode.None)
    }
  }
}
