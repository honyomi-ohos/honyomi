// 追踪器品牌徽标：使用 mihon 官方品牌图标资源，未知追踪器回退为文字占位

@Component
export struct TrackLogo {
  @Prop syncId: number = 0;
  @Prop logoName: string = '';
  @Prop color: string = '#888888';
  @Prop logoSize: number = 28;

  build() {
    if (this.hasIcon()) {
      Image(this.iconRes())
        .width(this.logoSize)
        .height(this.logoSize)
        .borderRadius(Math.round(this.logoSize * 0.22))
        .interpolation(ImageInterpolation.Medium)
    } else {
      Text(this.initials())
        .fontSize(Math.max(9, Math.round(this.logoSize * 0.36)))
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width(this.logoSize)
        .height(this.logoSize)
        .borderRadius(Math.round(this.logoSize * 0.28))
        .backgroundColor(this.color)
    }
  }

  private hasIcon(): boolean {
    return this.syncId === 1 || this.syncId === 2 || this.syncId === 3 || this.syncId === 4 ||
      this.syncId === 5 || this.syncId === 7 || this.syncId === 10 || this.syncId === 11;
  }

  private iconRes(): Resource {
    switch (this.syncId) {
      case 1:
        return $r('app.media.tracker_myanimelist');
      case 2:
        return $r('app.media.tracker_anilist');
      case 3:
        return $r('app.media.tracker_kitsu');
      case 4:
        return $r('app.media.tracker_shikimori');
      case 5:
        return $r('app.media.tracker_bangumi');
      case 7:
        return $r('app.media.tracker_mangaupdates');
      case 10:
        return $r('app.media.tracker_hikka');
      case 11:
        return $r('app.media.tracker_mangabaka');
      default:
        return $r('app.media.tracker_anilist');
    }
  }

  private initials(): string {
    const parts = this.logoName.split(' ');
    if (parts.length >= 2) {
      const a = parts[0].charAt(0);
      const b = parts[1].charAt(0);
      return `${a}${b}`.toUpperCase();
    }
    return this.logoName.substring(0, 2).toUpperCase();
  }
}
