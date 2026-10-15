// NSFW 标记徽章（红底白字小标签）：插件/源/仓库条目声明 nsfw 时显示
@Component
export struct NsfwTag {
  build() {
    Text('NSFW')
      .fontSize(9)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .backgroundColor('#E05252')
      .borderRadius(4)
      .padding({
        left: 4,
        right: 4,
        top: 1,
        bottom: 1
      })
  }
}
