// 隐私说明页（对齐 Mihon privacy policy，改为应用内展示）：
// 说明本地优先的数据存储、在线源/扩展、追踪服务与权限用途
import { ThemePalette } from '../../common/Theme';
import { NavGlassPage } from '../../common/HdsNavHost';

// 隐私说明小节：标题 + 正文（均走资源本地化）
interface PrivacySection {
  id: string;
  title: ResourceStr;
  body: ResourceStr;
}

@Component
export struct PrivacyPolicyPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  private policyScroller: Scroller = new Scroller();

  build() {
    NavGlassPage({ title: $r('app.string.privacy_policy_title'), scroller: this.policyScroller }) {
      Column() {
        Scroll(this.policyScroller) {
          Column({ space: 12 }) {
            Text($r('app.string.privacy_policy_intro'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pal.text)
              .lineHeight(22)
              .padding(16)
              .backgroundColor(this.pal.card)
              .borderRadius(16)
              .width('100%')
              .constraintSize({ maxWidth: 720 })

            ForEach(this.sections(), (section: PrivacySection) => {
              Column({ space: 6 }) {
                Text(section.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pal.text)
                Text(section.body)
                  .fontSize(13)
                  .fontColor(this.pal.sub)
                  .lineHeight(20)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding(16)
              .backgroundColor(this.pal.card)
              .borderRadius(16)
              .constraintSize({ maxWidth: 720 })
            }, (section: PrivacySection) => section.id)
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
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
    }
  }

  private sections(): PrivacySection[] {
    const sections: PrivacySection[] = [
      {
        id: 'local',
        title: $r('app.string.privacy_policy_local_title'),
        body: $r('app.string.privacy_policy_local_body')
      },
      {
        id: 'network',
        title: $r('app.string.privacy_policy_network_title'),
        body: $r('app.string.privacy_policy_network_body')
      },
      {
        id: 'tracking',
        title: $r('app.string.privacy_policy_tracking_title'),
        body: $r('app.string.privacy_policy_tracking_body')
      },
      {
        id: 'danmaku',
        title: $r('app.string.privacy_policy_danmaku_title'),
        body: $r('app.string.privacy_policy_danmaku_body')
      },
      {
        id: 'permissions',
        title: $r('app.string.privacy_policy_permissions_title'),
        body: $r('app.string.privacy_policy_permissions_body')
      },
      {
        id: 'contact',
        title: $r('app.string.privacy_policy_contact_title'),
        body: $r('app.string.privacy_policy_contact_body')
      }
    ];
    return sections;
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function PrivacyPolicyBuilder() {
  PrivacyPolicyPage()
}
