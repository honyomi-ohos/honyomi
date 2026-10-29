import { ThemePalette } from '../../common/Theme';

// 扩展可更新数量徽标（对齐 Mihon 扩展更新提示）：
// 读 AppStorage('extUpdateCount')（PluginService.checkExtensionUpdates 在刷新
// 仓库索引并比对版本后写入；键常量 PluginService.EXT_UPDATE_COUNT，因 AppKeys.ets
// 禁改未集中登记，装饰器处用字面量），数量 > 0 时显示数字角标，
// 供扩展列表入口（浏览页插件页签标题/图标右上角等）叠加展示
@Component
export struct ExtUpdateBadge {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('extUpdateCount') extUpdateCount: number = 0;
  // 角标高度（宽度按位数自适应，最小为正圆），默认小号适配图标右上角
  badgeHeight: number = 16;
  // 正文字号（随角标高度等比缩放）
  textSize: number = 10;

  build() {
    if (this.extUpdateCount > 0) {
      Text(this.badgeText())
        .fontSize(this.textSize)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor('#E05252')
        .height(this.badgeHeight)
        .constraintSize({ minWidth: this.badgeHeight })
        .borderRadius(this.badgeHeight / 2)
        .padding({ left: 4, right: 4 })
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
  }

  private badgeText(): string {
    return this.extUpdateCount > 99 ? '99+' : `${this.extUpdateCount}`;
  }
}
