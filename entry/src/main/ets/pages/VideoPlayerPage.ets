import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo, ChapterRepo, HistoryRepo } from '../data/Repos';
import { ReadingStatsRepo } from '../data/ReadingStats';
import { DownloadService } from '../data/DownloadService';
import { SourceRegistry } from '../source/Source';
import { Http } from '../net/Http';
import { MangaRecord, ChapterRecord, SVideo } from '../model/Models';
import { ReaderParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { AppIcon } from './components/AppIcon';

// 视频播放：AVPlayer + MediaSource（可带请求头）。进度记为播放位置毫秒。
@Component
export struct VideoPlayerPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State manga: MangaRecord = new MangaRecord();
  @State chapter: ChapterRecord = new ChapterRecord();
  @State videos: SVideo[] = [];
  @State qualityIndex: number = 0;
  @State loading: boolean = true;
  @State playing: boolean = false;
  @State positionMs: number = 0;
  @State durationMs: number = 0;
  @State errorText: string = '';
  @State prevId: number = 0;
  @State nextId: number = 0;
  private mangaId: number = -1;
  private chapterId: number = -1;
  private resumeMs: number = 0;
  private savedMs: number = 0;
  private surfaceId: string = '';
  private player: media.AVPlayer | undefined = undefined;
  private mediaFile: fs.File | undefined = undefined;
  private xCtrl: XComponentController = new XComponentController();
  private ticker: number = -1;
  private dragging: boolean = false;
  private localPath: string = '';
  private playGen: number = 0;

  aboutToDisappear(): void {
    this.persist(false);
    ReadingStatsRepo.flush();
    this.stopTicker();
    this.releasePlayer();
  }

  private async loadChapter(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    this.videos = [];
    this.playing = false;
    ReadingStatsRepo.flush();
    this.releasePlayer();
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await AppDb.ready(context);
      const chapter = await ChapterRepo.getById(this.chapterId);
      if (chapter === undefined) {
        Util.toastRes(this.getUIContext(), $r('app.string.reader_chapter_not_found'));
        this.pathStack.pop();
        return;
      }
      this.chapter = chapter;
      this.mangaId = chapter.mangaId;
      this.resumeMs = chapter.lastPageRead > 0 ? chapter.lastPageRead : 0;
      this.positionMs = this.resumeMs;
      this.savedMs = this.resumeMs;
      const manga = await MangaRepo.get(chapter.mangaId);
      if (manga !== undefined) {
        this.manga = manga;
      }
      this.localPath = DownloadService.localVideo(chapter.mangaId, chapter.id);
      if (this.localPath === '') {
        const source = SourceRegistry.get(this.manga.sourceKey);
        if (source === undefined) {
          throw new Error('源不可用');
        }
        this.videos = await source.getVideoList(chapter.url);
        if (this.videos.length === 0) {
          throw new Error('没有可播放的视频');
        }
      }
      this.qualityIndex = 0;
      await this.loadNeighbors();
      await HistoryRepo.upsert(chapter.mangaId, chapter.id, this.resumeMs);
      ReadingStatsRepo.begin(chapter.mangaId, chapter.id);
      this.loading = false;
      this.startCurrent();
    } catch (e) {
      this.errorText = (e as Error).message;
      Util.toastRes(this.getUIContext(), $r('app.string.reader_load_failed'), [this.errorText]);
      this.loading = false;
    }
  }

  private async loadNeighbors(): Promise<void> {
    const list = await ChapterRepo.listByManga(this.mangaId);
    let idx = -1;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === this.chapterId) {
        idx = i;
      }
    }
    this.prevId = idx > 0 ? list[idx - 1].id : 0;
    this.nextId = idx >= 0 && idx < list.length - 1 ? list[idx + 1].id : 0;
  }

  private startCurrent(): void {
    if (this.surfaceId === '') {
      return;
    }
    if (this.localPath !== '') {
      this.playFile(this.localPath);
      return;
    }
    if (this.qualityIndex < 0 || this.qualityIndex >= this.videos.length) {
      return;
    }
    const video = this.videos[this.qualityIndex];
    if (video.url.indexOf('file://') === 0) {
      this.playFile(video.url.substring('file://'.length));
      return;
    }
    this.playRemote(video);
  }

  private playFile(path: string): void {
    this.playGen += 1;
    const gen = this.playGen;
    this.releasePlayer();
    media.createAVPlayer().then((player: media.AVPlayer) => {
      if (gen !== this.playGen) {
        player.release();
        return;
      }
      this.bindPlayer(player);
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      this.mediaFile = file;
      const fdSrc: media.AVFileDescriptor = { fd: file.fd, offset: 0, length: stat.size };
      player.surfaceId = this.surfaceId;
      player.fdSrc = fdSrc;
    }).catch((e: Error) => {
      this.errorText = e.message;
    });
  }

  private playRemote(video: SVideo): void {
    this.playGen += 1;
    const gen = this.playGen;
    this.releasePlayer();
    media.createAVPlayer().then((player: media.AVPlayer) => {
      if (gen !== this.playGen) {
        player.release();
        return;
      }
      this.bindPlayer(player);
      player.surfaceId = this.surfaceId;
      const headers = Http.headersFor(video.url, video.headers);
      const source = media.createMediaSourceWithUrl(video.url, headers);
      const strategy: media.PlaybackStrategy = { preferredWidth: 0, preferredHeight: 0 };
      player.setMediaSource(source, strategy);
    }).catch((e: Error) => {
      this.errorText = e.message;
    });
  }

  private bindPlayer(player: media.AVPlayer): void {
    this.player = player;
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (state === 'initialized') {
        player.prepare();
      } else if (state === 'prepared') {
        this.durationMs = player.duration > 0 ? player.duration : 0;
        if (this.resumeMs > 0 && (this.durationMs === 0 || this.resumeMs < this.durationMs)) {
          player.seek(this.resumeMs, media.SeekMode.SEEK_PREV_SYNC);
        }
        player.play();
        this.playing = true;
        this.startTicker();
      } else if (state === 'playing') {
        this.playing = true;
      } else if (state === 'paused' || state === 'completed' || state === 'stopped') {
        this.playing = false;
        if (state === 'completed') {
          this.persist(true);
        }
      } else if (state === 'error') {
        this.playing = false;
        this.errorText = '播放失败';
      }
    });
    player.on('error', (_err: Error) => {
      this.errorText = '播放失败';
      this.playing = false;
    });
  }

  private startTicker(): void {
    this.stopTicker();
    this.ticker = setInterval(() => {
      const player = this.player;
      if (player === undefined || this.dragging) {
        return;
      }
      if (player.currentTime >= 0) {
        this.positionMs = player.currentTime;
      }
      if (player.duration > 0) {
        this.durationMs = player.duration;
      }
      if (Math.abs(this.positionMs - this.savedMs) >= 5000) {
        this.persist(false);
      }
      ReadingStatsRepo.tick();
    }, 500);
  }

  private stopTicker(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  private releasePlayer(): void {
    const player = this.player;
    this.player = undefined;
    this.playing = false;
    if (player !== undefined) {
      player.release();
    }
    if (this.mediaFile !== undefined) {
      try {
        fs.closeSync(this.mediaFile);
      } catch (e) {
        // 已关闭
      }
      this.mediaFile = undefined;
    }
  }

  private togglePlay(): void {
    const player = this.player;
    if (player === undefined) {
      this.startCurrent();
      return;
    }
    if (this.playing) {
      player.pause();
      this.persist(false);
    } else {
      player.play();
    }
  }

  private seekTo(ms: number): void {
    const player = this.player;
    if (player === undefined) {
      return;
    }
    this.positionMs = ms;
    player.seek(ms, media.SeekMode.SEEK_PREV_SYNC);
    this.persist(false);
  }

  private persist(finished: boolean): void {
    if (this.chapterId <= 0) {
      return;
    }
    const pos = finished && this.durationMs > 0 ? this.durationMs : Math.floor(this.positionMs);
    this.savedMs = pos;
    ChapterRepo.setLastPageRead(this.chapterId, pos).catch(() => {
    });
    HistoryRepo.upsert(this.mangaId, this.chapterId, pos).catch(() => {
    });
    if (finished || (this.durationMs > 0 && pos >= this.durationMs * 0.9)) {
      ChapterRepo.setRead(this.chapterId, true).catch(() => {
      });
    }
  }

  private pickQuality(index: number): void {
    if (index === this.qualityIndex) {
      return;
    }
    this.resumeMs = Math.floor(this.positionMs);
    this.qualityIndex = index;
    this.startCurrent();
  }

  private openChapter(id: number): void {
    if (id <= 0) {
      return;
    }
    this.persist(false);
    this.stopTicker();
    this.chapterId = id;
    this.loadChapter();
  }

  private clock(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000));
    const m = Math.floor(total / 60);
    const s = total % 60;
    const ss = s < 10 ? `0${s}` : `${s}`;
    return `${m}:${ss}`;
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 24, tint: Color.White })
            .onClick(() => {
              this.pathStack.pop();
            })
          Column() {
            Text(this.manga.title)
              .fontSize(16)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.chapter.name)
              .fontSize(12)
              .fontColor('#CCCCCC')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 12, right: 16, top: this.statusBarH + 8, bottom: 8 })
        .backgroundColor('#111111')

        Stack() {
          XComponent({
            id: 'videoSurface',
            type: XComponentType.SURFACE,
            controller: this.xCtrl
          })
            .width('100%')
            .height('100%')
            .onLoad(() => {
              this.surfaceId = this.xCtrl.getXComponentSurfaceId();
              if (!this.loading && this.errorText === '' && this.player === undefined) {
                this.startCurrent();
              }
            })
          if (this.loading) {
            LoadingProgress().width(36).height(36).color(Color.White)
          } else if (this.errorText !== '') {
            Text(this.errorText)
              .fontSize(13)
              .fontColor(Color.White)
              .padding(16)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#000000')

        Column() {
          Slider({
            value: this.positionMs,
            min: 0,
            max: this.durationMs > 0 ? this.durationMs : 1,
            step: 1000
          })
            .width('100%')
            .selectedColor(this.pal.primary)
            .onChange((v: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                this.dragging = true;
                this.positionMs = v;
              } else {
                this.dragging = false;
                this.seekTo(v);
              }
            })
          Row() {
            Text(this.clock(this.positionMs))
              .fontSize(12)
              .fontColor(this.pal.sub)
            Blank()
            Text(this.playing ? $r('app.string.video_pause') : $r('app.string.video_play'))
              .fontSize(15)
              .fontColor('#FFFFFF')
              .backgroundColor(this.pal.primary)
              .borderRadius(16)
              .padding({ left: 18, right: 18, top: 6, bottom: 6 })
              .onClick(() => {
                this.togglePlay();
              })
            Blank()
            Text(this.clock(this.durationMs))
              .fontSize(12)
              .fontColor(this.pal.sub)
          }
          .width('100%')
          .margin({ top: 4 })

          if (this.videos.length > 1) {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.videos, (video: SVideo, index: number) => {
                  Text(video.quality)
                    .fontSize(12)
                    .fontColor(this.qualityIndex === index ? '#FFFFFF' : this.pal.text)
                    .backgroundColor(this.qualityIndex === index ? this.pal.primary : this.pal.chip)
                    .borderRadius(12)
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .onClick(() => {
                      this.pickQuality(index);
                    })
                }, (video: SVideo, index: number) => `q-${index}-${video.quality}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .margin({ top: 10 })
          }

          Row() {
            Text($r('app.string.video_prev'))
              .fontSize(14)
              .fontColor(this.prevId > 0 ? this.pal.primary : this.pal.sub)
              .onClick(() => {
                this.openChapter(this.prevId);
              })
            Blank()
            Text($r('app.string.video_next'))
              .fontSize(14)
              .fontColor(this.nextId > 0 ? this.pal.primary : this.pal.sub)
              .onClick(() => {
                this.openChapter(this.nextId);
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: this.navBarH + 12 })
        .backgroundColor(this.pal.bg)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params = ctx.pathInfo.param as ReaderParams;
      if (params !== undefined && params !== null) {
        this.mangaId = params.mangaId;
        this.chapterId = params.chapterId;
      }
      this.loadChapter();
    })
  }
}
