// BT 源标记徽章（蓝底白字小标签）：插件/源条目声明 bt 时显示
@Component
export struct BtTag {
  build() {
    Text('BT')
      .fontSize(9)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .backgroundColor('#3B82F6')
      .borderRadius(4)
      .padding({
        left: 4,
        right: 4,
        top: 1,
        bottom: 1
      })
  }
}
