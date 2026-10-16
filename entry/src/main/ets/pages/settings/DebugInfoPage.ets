import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { ThemePalette } from '../../common/Theme';
import { Util } from '../../common/Util';
import { PageHeader } from '../components/PageHeader';
import { PrefGroup } from '../components/Prefs';

// 调试信息行模型：标签 + 值
interface DebugRow {
  label: string;
  value: string;
}

// 调试信息内容（对齐 Mihon DebugInfoScreen）：
// 应用版本 / 设备型号 / 设备类型 / 系统版本 / API 版本 / 屏幕 / 语言
@Component
export struct DebugInfoContent {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @State rows: DebugRow[] = [];

  aboutToAppear(): void {
    this.rows = this.buildRows();
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup() {
          ForEach(this.rows, (row: DebugRow, index: number) => {
            if (index > 0) {
              Divider().color(this.pal.divider).margin({ left: 16 })
            }
            Row() {
              Text(row.label)
                .fontSize(15)
                .fontColor(this.pal.sub)
              Blank()
              Text(row.value)
                .fontSize(15)
                .fontColor(this.pal.text)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: '62%' })
                .textAlign(TextAlign.End)
            }
            .width('100%')
            .constraintSize({ minHeight: 52 })
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .alignItems(VerticalAlign.Center)
          }, (row: DebugRow, index: number) => `dbg-${index}-${row.label}`)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  private buildRows(): DebugRow[] {
    const ui = this.getUIContext();
    const rows: DebugRow[] = [];
    // 应用版本
    let version = '';
    let versionCode = 0;
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      version = info.versionName;
      versionCode = info.versionCode;
    } catch (_e) {
    }
    rows.push({
      label: Util.resStr(ui, $r('app.string.debug_app_version')),
      value: version !== '' ? `${version} (${versionCode})` : '—'
    });
    // 设备
    rows.push({
      label: Util.resStr(ui, $r('app.string.debug_device_model')),
      value: deviceInfo.productModel
    });
    rows.push({
      label: Util.resStr(ui, $r('app.string.debug_device_type')),
      value: deviceInfo.deviceType
    });
    // 系统
    rows.push({
      label: Util.resStr(ui, $r('app.string.debug_system_version')),
      value: `${deviceInfo.osFullName} ${deviceInfo.displayVersion}`
    });
    rows.push({
      label: Util.resStr(ui, $r('app.string.debug_api_version')),
      value: `${deviceInfo.sdkApiVersion}`
    });
    // 屏幕
    let screen = '—';
    try {
      const d = display.getDefaultDisplaySync();
      screen = `${d.width}x${d.height} @ ${d.refreshRate}Hz (${d.densityDPI}dpi)`;
    } catch (_e) {
    }
    rows.push({ label: Util.resStr(ui, $r('app.string.debug_screen')), value: screen });
    // 语言
    let lang = '—';
    try {
      lang = i18n.System.getSystemLanguage();
    } catch (_e) {
    }
    rows.push({ label: Util.resStr(ui, $r('app.string.debug_language')), value: lang });
    return rows;
  }
}

// 调试信息路由壳（手机/平板窄屏 push 进入）
@Component
export struct DebugInfoPage {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: $r('app.string.pref_debug_info') })
        DebugInfoContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pal.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(this.pal.bg)
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function DebugInfoBuilder() {
  DebugInfoPage()
}
