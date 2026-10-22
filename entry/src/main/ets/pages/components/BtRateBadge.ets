// BT 实时速率徽标：引擎启动期间一列两行小字显示当前 BT 会话下载/上传
// 速率（↓/↑）。数据源 AppStorage（btDownRate/btUpRate，字节/秒，BtModule
// 聚合引擎 1s 进度快照写入，无活动任务自动归零）；btEngineStarted 为 false
// （引擎未启动/已停止）时整体隐藏
import { ThemePalette } from '../../common/Theme';

@Component
export struct BtRateBadge {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('btEngineStarted') engineStarted: boolean = false;
  @StorageProp('btDownRate') downRate: number = 0;
  @StorageProp('btUpRate') upRate: number = 0;

  build() {
    if (this.engineStarted) {
      Column({ space: 1 }) {
      // 箭头置于速率之后：整体右对齐，箭头固定贴右，速率数字向左伸缩不抖动
      Row({ space: 3 }) {
        Text(this.rateText(this.downRate))
          .fontSize(10)
          .fontColor(this.pal.sub)
          .maxLines(1)
        Text('↓')
          .fontSize(10)
          .fontColor(this.pal.sub)
      }
      Row({ space: 3 }) {
        Text(this.rateText(this.upRate))
          .fontSize(10)
          .fontColor(this.pal.sub)
          .maxLines(1)
        Text('↑')
          .fontSize(10)
          .fontColor(this.pal.sub)
      }
      }
      .alignItems(HorizontalAlign.End)
    }
  }

  // 字节/秒 → KB/s（<1MB，整数）或 MB/s（≥1MB，一位小数）
  private rateText(bytesPerSec: number): ResourceStr {
    const kbps = Math.round(bytesPerSec / 1024);
    if (kbps < 1024) {
      return $r('app.string.bt_limit_kb', kbps);
    }
    return $r('app.string.bt_rate_mb', (kbps / 1024).toFixed(1));
  }
}
