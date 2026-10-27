import { ThemePalette } from '../../common/Theme';
import { Settings } from '../../common/Settings';
import { Util } from '../../common/Util';
import { BtFlow } from '../../data/BtFlow';
import { NavGlassPage } from '../../common/HdsNavHost';
import { AppKeys } from '../../common/AppKeys';

// BT Peer 过滤器编辑页（对齐 animeko AnitorrentEngineSettings 独立页模式）：
// 每行一条规则，"from-to" 区间或单个 IP（IPv4/IPv6），空 = 不过滤。
// 保存时仅做轻量格式校验，严格解析（lt::make_address + 区间合法性）由桥接层完成，
// 解析失败抛错并 toast。
@Component
export struct BtPeerFilterPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  // 编辑草稿（TextArea 双向暂存，保存时校验+落库）
  @State draft: string = '';
  // 路由栈：NavDestination onReady 时从自身上下文获取（官方推荐方式）
  pathStack: NavPathStack = new NavPathStack();
  // 标题栏滚动联动：绑定本页滚动容器
  private peerFilterScroller: Scroller = new Scroller();

  // 轻量校验：非空行须为 "from-to" 或单个 IP，字符集限数字/字母/./:/-

  build() {
    NavGlassPage({
      title: $r('app.string.bt_peer_filter_title'),
      scroller: this.peerFilterScroller,
      onReady: (ctx: NavDestinationContext): void => {
        this.pathStack = ctx.pathStack;
      }
    }) {
      Column() {
        Scroll(this.peerFilterScroller) {
          Column({ space: 12 }) {
            Text($r('app.string.bt_peer_filter_hint'))
              .fontSize(13)
              .fontColor(this.pal.sub)
              .width('100%')
              .textAlign(TextAlign.Start)
            TextArea({ text: this.draft, placeholder: $r('app.string.bt_peer_filter_hint') })
              .fontSize(14)
              .height(240)
              .width('100%')
              .enabled(true)
              .onChange((value: string) => {
                this.draft = value;
              })
            Button($r('app.string.common_save'))
              .width('100%')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .backgroundColor(this.pal.primary)
              .onClick(() => {
                this.save();
              })
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 4,
            bottom: 24
          })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
    }
  }

  aboutToAppear(): void {
    this.draft = Settings.getBtPeerFilter();
  }

  // 严格 IP 解析在桥接层（保存后 applyPeerFilterLive 失败会 toast）
  private isValidRule(line: string): boolean {
    const parts: string[] = line.split('-');
    if (parts.length > 2) {
      return false;
    }
    for (let i = 0; i < parts.length; i += 1) {
      const ip: string = parts[i];
      if (ip.length === 0 || ip.length > 45) {
        return false;
      }
      if (!ip.includes('.') && !ip.includes(':')) {
        return false;
      }
    }
    return true;
  }

  private invalidRuleLine(): number {
    const lines: string[] = this.draft.split('\n');
    for (let i = 0; i < lines.length; i += 1) {
      const line: string = lines[i].trim();
      if (line.length > 0 && !this.isValidRule(line)) {
        return i + 1;
      }
    }
    return -1;
  }

  private save(): void {
    const badLine: number = this.invalidRuleLine();
    if (badLine > 0) {
      Util.toastRes(this.getUIContext(), $r('app.string.bt_peer_filter_invalid'), [badLine]);
      return;
    }
    Settings.setBtPeerFilter(this.draft);
    // 即时下发引擎（未启动静默，下次启动由 ensureStarted 读取）
    BtFlow.applyPeerFilterLive();
    // 通知 BT 设置页刷新规则计数（返回后无状态变化不会重渲染）
    AppStorage.setOrCreate(AppKeys.BT_PEER_FILTER_TICK,
      (AppStorage.get<number>(AppKeys.BT_PEER_FILTER_TICK) ?? 0) + 1);
    this.pathStack.pop();
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function BtPeerFilterBuilder() {
  BtPeerFilterPage()
}
