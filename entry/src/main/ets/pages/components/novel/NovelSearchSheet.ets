// 小说章内搜索面板：关键词输入 + 命中列表（命中词高亮），点击命中跳转对应段落/页
import { ThemePalette } from '../../../common/Theme';
import { AppIcon } from '../AppIcon';

// 搜索命中：段落下标（非插图章=行下标；插图章=文本块 ttsIdx）+ 三段式摘要
export class NovelSearchHit {
  paraIdx: number = 0;
  before: string = '';
  match: string = '';
  after: string = '';

  // 从段落文本构造命中摘要：命中词前后各取少量上下文，超长以省略号标记
  static make(paraIdx: number, text: string, pos: number, len: number): NovelSearchHit {
    const hit = new NovelSearchHit();
    hit.paraIdx = paraIdx;
    const beforeCtx = 14;
    const afterCtx = 32;
    const start = Math.max(0, pos - beforeCtx);
    const end = Math.min(text.length, pos + len + afterCtx);
    hit.before = (start > 0 ? '…' : '') + text.substring(start, pos);
    hit.match = text.substring(pos, pos + len);
    hit.after = text.substring(pos + len, end) + (end < text.length ? '…' : '');
    return hit;
  }
}

@Component
export struct NovelSearchSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop hits: NovelSearchHit[] = [];
  @State query: string = '';
  onSearch: (q: string) => void = (q: string): void => {
  };
  onJump: (hit: NovelSearchHit) => void = (hit: NovelSearchHit): void => {
  };

  build() {
    Column() {
      Row({ space: 8 }) {
        AppIcon({ name: 'search', iconSize: 18, tint: this.pal.sub })
        TextInput({ text: this.query, placeholder: $r('app.string.novel_search_hint') })
          .fontSize(14)
          .fontColor(this.pal.text)
          .placeholderColor(this.pal.sub)
          .placeholderFont({ size: 14 })
          .backgroundColor(Color.Transparent)
          .padding({ top: 0, bottom: 0 })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.query = value;
            this.onSearch(value);
          })
          .onSubmit(() => {
            this.onSearch(this.query);
          })
      }
      .width('100%')
      .height(44)
      .padding({ left: 14, right: 14 })
      .borderRadius(22)
      .backgroundColor(this.pal.chip)

      if (this.hits.length === 0) {
        Column() {
          Text($r('app.string.novel_search_empty'))
            .fontSize(13)
            .fontColor(this.pal.sub)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ initialIndex: 0 }) {
          ForEach(this.hits, (hit: NovelSearchHit, i: number) => {
            ListItem() {
              Column() {
                Text() {
                  Span(hit.before)
                    .fontSize(13)
                    .fontColor(this.pal.text)
                  Span(hit.match)
                    .fontSize(13)
                    .fontColor(this.pal.primary)
                    .fontWeight(FontWeight.Medium)
                  Span(hit.after)
                    .fontSize(13)
                    .fontColor(this.pal.text)
                }
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              }
              .width('100%')
              .padding({ left: 4, right: 4, top: 12, bottom: 12 })
              .onClick(() => {
                this.onJump(hit);
              })
            }
          }, (hit: NovelSearchHit, i: number) => `${i}#${hit.paraIdx}#${hit.match}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({ strokeWidth: 0.5, color: this.pal.divider, startMargin: 4, endMargin: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }
}
