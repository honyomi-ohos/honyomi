import { common } from '@kit.AbilityKit';
import { AppDb } from '../data/AppDb';
import { MangaRepo } from '../data/Repos';
import { SourceRegistry, Source } from '../source/Source';
import { MangaRecord, SManga, MangasPage } from '../model/Models';
import { DetailParams } from '../model/RouteParams';
import { ThemePalette } from '../common/Theme';
import { Util } from '../common/Util';
import { EmptyScreen } from './components/EmptyScreen';
import { MangaRow } from './components/MangaRow';
import { AppIcon } from './components/AppIcon';

// 全局搜索结果分节（每源一节）
export class SearchSection {
  sourceKey: string = '';
  name: string = '';
  results: MangaRecord[] = [];
  state: string = 'loading'; // loading | done | error
}

// 全局搜索页（图源 Tab 顶栏按钮进入）：一次搜索所有已启用源
@Component
export struct GlobalSearchPage {
  pathStack: NavPathStack = new NavPathStack();
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('statusBarH') statusBarH: number = 0;
  @StorageProp('navBarH') navBarH: number = 0;
  @State query: string = '';
  @State sections: SearchSection[] = [];
  @State searching: boolean = false;

  private updateSection(sourceKey: string, results: MangaRecord[], state: string): void {
    const next: SearchSection[] = [];
    for (const s of this.sections) {
      if (s.sourceKey === sourceKey) {
        const updated: SearchSection = new SearchSection();
        updated.sourceKey = s.sourceKey;
        updated.name = s.name;
        updated.results = results;
        updated.state = state;
        next.push(updated);
      } else {
        next.push(s);
      }
    }
    this.sections = next;
  }

  private searchOne(source: Source, q: string): void {
    source.getSearchManga(1, q).then(async (result: MangasPage) => {
      const records: MangaRecord[] = [];
      for (const m of result.mangas) {
        const record = new MangaRecord();
        record.sourceKey = source.key;
        record.url = m.key;
        record.title = m.title;
        record.thumbnailUrl = m.coverUrl;
        record.contentType = source.contentType;
        records.push(record);
      }
      this.updateSection(source.key, records, 'done');
    }).catch((_e: Error) => {
      this.updateSection(source.key, [], 'error');
    });
  }

  private sourceTitle(s: Source): string {
    const context = Util.hostAbilityContext(this.getUIContext());
    if (s.key === 'local') {
      return context.resourceManager.getStringSync($r('app.string.browse_local_source_name').id);
    }
    if (s.key === 'local_novel') {
      return context.resourceManager.getStringSync($r('app.string.browse_local_novel_name').id);
    }
    if (s.key === 'local_video') {
      return context.resourceManager.getStringSync($r('app.string.browse_local_video_name').id);
    }
    return s.name;
  }

  private startSearch(): Promise<void> {
    const q = this.query.trim();
    if (q === '') {
      return Promise.resolve();
    }
    const sources: Source[] = SourceRegistry.all();
    const sections: SearchSection[] = [];
    for (const s of sources) {
      const section: SearchSection = new SearchSection();
      section.sourceKey = s.key;
      section.name = this.sourceTitle(s);
      sections.push(section);
    }
    this.sections = sections;
    this.searching = true;
    const context = Util.hostAbilityContext(this.getUIContext());
    return AppDb.ready(context).then(() => {
      for (const s of sources) {
        this.searchOne(s, q);
      }
    }).catch((_e: Error) => {
      this.searching = false;
    });
  }

  async openDetail(record: MangaRecord): Promise<void> {
    try {
      const context = Util.hostAbilityContext(this.getUIContext());
      await AppDb.ready(context);
      const m: SManga = {
        key: record.url,
        title: record.title,
        coverUrl: record.thumbnailUrl,
        author: record.author,
        description: record.description,
        genre: record.genre,
        status: record.status,
      };
      const id = await MangaRepo.upsertFromSource(record.sourceKey, m, record.contentType);
      const params: DetailParams = { mangaId: id };
      this.pathStack.pushPathByName('MangaDetail', params);
    } catch (e) {
      Util.toastRes(this.getUIContext(), $r('app.string.browse_open_detail_failed'));
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row() {
          AppIcon({ name: 'arrow_back', iconSize: 24 })
            .onClick(() => {
              this.pathStack.pop();
            })
          TextInput({ placeholder: $r('app.string.global_search_hint') })
            .layoutWeight(1)
            .height(38)
            .backgroundColor(this.pal.card)
            .enterKeyType(EnterKeyType.Search)
            .onChange((value: string) => {
              this.query = value;
            })
            .onSubmit(() => {
              this.startSearch();
            })
          Button($r('app.string.common_search'))
            .fontSize(14)
            .height(38)
            .backgroundColor(this.pal.primary)
            .margin({ left: 8 })
            .onClick(() => {
              this.startSearch();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.statusBarH + 10, bottom: 10 })

        // 结果
        if (this.sections.length === 0) {
          Column() {
            EmptyScreen({ message: $r('app.string.global_search_hint') })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              ForEach(this.sections, (section: SearchSection) => {
                Column() {
                  Row() {
                    Text(section.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.pal.text)
                      .layoutWeight(1)
                    if (section.state === 'loading') {
                      LoadingProgress()
                        .width(16)
                        .height(16)
                        .color(this.pal.primary)
                    } else if (section.state === 'error') {
                      Text($r('app.string.global_search_failed'))
                        .fontSize(12)
                        .fontColor('#E05252')
                    } else {
                      Text(`${section.results.length}`)
                        .fontSize(12)
                        .fontColor(this.pal.sub)
                    }
                  }
                  .width('100%')
                  .margin({ bottom: 4 })

                  if (section.state === 'done' && section.results.length === 0) {
                    Text($r('app.string.browse_no_results'))
                      .fontSize(12)
                      .fontColor(this.pal.sub)
                      .width('100%')
                      .padding({ top: 4, bottom: 4 })
                  } else {
                    ForEach(section.results, (record: MangaRecord) => {
                        MangaRow({
                          record: record,
                          onRowClick: (r: MangaRecord): void => {
                           this.openDetail(r);
                         },
                       })
                    }, (record: MangaRecord) => `gs-${section.sourceKey}-${record.url}`)
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(16)
                .backgroundColor(this.pal.card)
                .borderRadius(14)
                .margin({ left: 16, right: 16, top: 8 })
              }, (section: SearchSection) => `sec-${section.sourceKey}-${section.state}-${section.results.length}`)
            }
            .width('100%')
            .padding({ bottom: this.navBarH + 24 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function GlobalSearchBuilder() {
  GlobalSearchPage()
}
