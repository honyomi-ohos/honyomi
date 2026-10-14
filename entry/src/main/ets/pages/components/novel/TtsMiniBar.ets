import { ThemePalette } from '../../../common/Theme';
import { ChapterRecord, MangaRecord } from '../../../model/Models';
import { TtsPlaybackService, TtsServiceStateHandler, TtsServiceChapterHandler } from '../../../common/TtsPlaybackService';
import { AppIcon } from '../AppIcon';
import { SmartImage } from '../SmartImage';

// 听书迷你条内容行（对齐 MusicHome HomeMiniBarPlayer）：
// Row [ 圆形封面 | 章节/书名(点击打开播放器) | 播放暂停 | 停止 ]，高 56。
// 胶囊外壳由宿主提供：手机端挂入 HdsTabs barFloatingStyle.miniBar（HDS 绘制
// 背景并与浮动页签条贴合悬浮于导航条上方）；PC/宽屏端由 Index 包裹胶囊悬于右下角。
@Component
export struct TtsMiniBar {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State active: boolean = false;
  @State playing: boolean = false;
  @State chapterName: string = '';
  @State mangaTitle: string = '';
  @State coverUrl: string = '';
  @State coverSource: string = '';
  onOpenPlayer: () => void = (): void => {};

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
    this.coverUrl = m !== undefined ? m.thumbnailUrl : '';
    this.coverSource = m !== undefined ? m.sourceKey : '';
    this.chapterName = ch !== undefined ? ch.name : '';
  }

  build() {
    if (this.active) {
      Row({ space: 12 }) {
        // 圆形封面（点击打开播放器）
        SmartImage({ url: this.coverUrl, sourceKey: this.coverSource, fill: true })
          .width(40)
          .height(40)
          .borderRadius(20)
          .clip(true)
          .onClick(() => {
            this.onOpenPlayer();
          })

        // 章节名 / 书名（点击打开播放器）
        Column({ space: 2 }) {
          Text(this.chapterName)
            .fontSize(13)
            .fontWeight(600)
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
        .onClick(() => {
          this.onOpenPlayer();
        })

        // 播放/暂停
        AppIcon({ name: this.playing ? 'pause' : 'play_arrow', iconSize: 24, tint: this.pal.text })
          .onClick(() => {
            TtsPlaybackService.toggle();
          })

        // 停止
        AppIcon({ name: 'close', iconSize: 20, tint: this.pal.sub })
          .onClick(() => {
            TtsPlaybackService.stop();
          })
      }
      .alignItems(VerticalAlign.Center)
      .height(56)
      // 收起态胶囊较窄：左边距 8 让封面在最小状态下居中
      .padding({ left: 8, right: 16, top: 6, bottom: 6 })
    } else {
      Column()
        .width(0)
        .height(0)
        .hitTestBehavior(HitTestMode.None)
    }
  }
}
