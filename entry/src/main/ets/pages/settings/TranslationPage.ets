// 翻译设置页：总开关 + 引擎优先级（长按拖拽排序，点击行打开该引擎密钥配置）+ 连通性测试。
// 引擎凭据均不回显明文，行尾仅显示「已配置/未配置/无需配置」状态
// 拖拽参考官方 grid-drag-sort 示例的"直接拖拽"模式（同分类管理）：
// 长按浮起（translate/zIndex/scale）→ 跟手位移 → 越过半行高时弹簧动画换位 → 松手持久化
import { curves } from '@kit.ArkUI';
import { Settings } from '../../common/Settings';
import { ThemePalette } from '../../common/Theme';
import { NavGlassPage } from '../../common/HdsNavHost';
import { Util } from '../../common/Util';
import { TranslationService } from '../../translate/TranslationService';
import { TransLangs } from '../../translate/TransLangs';
import { PrefGroup, PrefSwitchRow, TextRow } from '../components/Prefs';
import { AppIcon } from '../components/AppIcon';
import { InputDialog, CredentialsDialog } from '../components/Dialogs';
import { PickerSheet } from '../components/PickerSheet';
import { SheetPreset } from '../components/SheetPreset';

// 翻译设置内容（lg 双栏右栏 + 窄屏路由页共用）
@Component
export struct TranslationContent {
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @StorageProp('windowW') windowW: number = 0;
  // 引擎优先级内存镜像（持久化 CSV：Settings.transEngineOrder）
  @State engineOrder: string[] = [];
  @State testing: boolean = false;
  // 目标语言（应用内语言码，见 TransLangs.TARGETS）
  @State targetLang: string = 'zh';
  // 目标语言选择弹层
  @State showLangSheet: boolean = false;
  // 拖拽排序状态
  @State dragId: string = '';
  @State offsetY: number = 0;
  @State rowH: number = 0;
  private dragRefOffsetY: number = 0;
  private panning: boolean = false;
  private orderDirty: boolean = false;

  aboutToAppear(): void {
    this.refreshState();
  }

  @Builder
  engineRow(id: string) {
    Row() {
      AppIcon({ name: 'drag_handle', iconSize: 20 })
      Text(this.engineName(id))
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .margin({ left: 14 })
        .maxLines(1)
      Text(this.engineStatus(id))
        .fontSize(12)
        .fontColor(this.pal.sub)
        .maxLines(1)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.dragId === id ? this.pal.card : Color.Transparent)
    .borderRadius(this.dragId === id ? 12 : 0)
    .shadow(this.dragId === id
      ? {
        radius: 20,
        offsetX: 0,
        offsetY: 6,
        color: this.isDark ? '#99000000' : '#2E000000'
      }
      : { radius: 0 })
    .scale(this.dragId === id ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
    .zIndex(this.dragId === id ? 1 : 0)
    .translate({ y: this.dragId === id ? this.offsetY : 0 })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // 行高仅在首行测量一次（各行等高，作为换位阈值）
      if (this.rowH <= 0 && typeof newArea.height === 'number') {
        this.rowH = newArea.height;
      }
    })
    .gesture(
      GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, duration: 300 })
          .onAction(() => {
            // 长按浮起待拖拽
            this.getUIContext().animateTo({ duration: 120, curve: Curve.Friction }, (): void => {
              this.dragId = id;
              this.offsetY = 0;
            });
          })
          .onActionEnd(() => {
            // 长按后未拖动直接松手：取消浮起
            if (!this.panning) {
              this.endDrag();
            }
          }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 0 })
          .onActionStart(() => {
            this.panning = true;
            this.dragRefOffsetY = 0;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.offsetY = event.offsetY - this.dragRefOffsetY;
            const index: number = this.engineOrder.indexOf(id);
            if (this.rowH <= 0 || index < 0) {
              return;
            }
            // 越过半行高时弹簧动画换位（其余行滑动让位）
            this.getUIContext().animateTo(
              { curve: curves.interpolatingSpring(0, 1, 400, 38) }, (): void => {
              if (this.offsetY >= this.rowH / 2 && index < this.engineOrder.length - 1) {
                this.offsetY -= this.rowH;
                this.dragRefOffsetY += this.rowH;
                this.itemMove(index, index + 1);
              } else if (this.offsetY <= -this.rowH / 2 && index > 0) {
                this.offsetY += this.rowH;
                this.dragRefOffsetY -= this.rowH;
                this.itemMove(index, index - 1);
              }
            });
          })
          .onActionEnd(() => {
            this.panning = false;
            this.endDrag();
          })
          .onActionCancel(() => {
            this.panning = false;
            this.endDrag();
          })
      )
    )
    // 点击行打开该引擎的密钥配置（免密钥引擎提示无需配置）
    .onClick(() => {
      this.openEngineConfig(id);
    })
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        PrefGroup({ groupTitle: $r('app.string.trans_title') }) {
          PrefSwitchRow({
            title: $r('app.string.trans_enable'),
            subtitle: $r('app.string.trans_enable_sub'),
            initValue: Settings.getTransEnabled(),
            apply: (value: boolean): void => {
              Settings.setTransEnabled(value);
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          TextRow({
            title: $r('app.string.trans_target'),
            value: TransLangs.labelOf(this.targetLang),
            onTap: (): void => {
              this.showLangSheet = true;
            }
          })
          Divider().color(this.pal.divider).margin({ left: 16 })
          TextRow({
            title: $r('app.string.trans_test'),
            value: this.testing ? $r('app.string.trans_test_running') : '',
            onTap: (): void => {
              this.runTest();
            }
          })
        }

        PrefGroup({ groupTitle: $r('app.string.trans_engines') }) {
          ForEach(this.engineOrder, (id: string, index: number) => {
            if (index > 0) {
              Divider().color(this.pal.divider).margin({ left: 16 })
            }
            this.engineRow(id)
          }, (id: string) => `engine-${id}`)
        }

        Text($r('app.string.trans_engines_hint'))
          .fontSize(11)
          .fontColor(this.pal.sub)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .bindSheet($$this.showLangSheet, this.langSheetBuilder(),
      SheetPreset.fit(this.windowW, {
        title: $r('app.string.trans_target'),
        showClose: false
      }))
  }

  // 目标语言选择弹层（原生名展示，当前项高亮）
  @Builder
  langSheetBuilder() {
    PickerSheet({
      options: this.targetLabels(),
      selectedIndex: TransLangs.indexOf(this.targetLang),
      onPick: (index: number): void => {
        this.showLangSheet = false;
        if (index < 0 || index >= TransLangs.TARGETS.length) {
          return;
        }
        const code: string = TransLangs.TARGETS[index].code;
        Settings.setTransTargetLang(code);
        this.targetLang = code;
      }
    })
  }

  // 目标语言选项（原生名数组）
  private targetLabels(): ResourceStr[] {
    const labels: ResourceStr[] = [];
    for (const lang of TransLangs.TARGETS) {
      labels.push(lang.label);
    }
    return labels;
  }

  // ---- 引擎状态 ----

  private engineName(id: string): ResourceStr {
    if (id === 'baidu') {
      return $r('app.string.trans_baidu');
    }
    if (id === 'youdao') {
      return $r('app.string.trans_youdao');
    }
    if (id === 'caiyun') {
      return $r('app.string.trans_caiyun');
    }
    if (id === 'deepl') {
      return $r('app.string.trans_deepl');
    }
    if (id === 'microsoft') {
      return $r('app.string.trans_microsoft');
    }
    if (id === 'tencent') {
      return $r('app.string.trans_tencent');
    }
    if (id === 'volcano') {
      return $r('app.string.trans_volcano');
    }
    if (id === 'niutrans') {
      return $r('app.string.trans_niutrans');
    }
    return $r('app.string.trans_google');
  }

  private engineStatus(id: string): ResourceStr {
    if (id === 'deepl' || id === 'google' || id === 'microsoft') {
      return $r('app.string.trans_status_free');
    }
    return TranslationService.isEngineConfigured(id)
      ? $r('app.string.trans_status_ready') : $r('app.string.trans_status_missing');
  }

  // 数组内移动引擎（换位），标记顺序已变更
  private itemMove(index: number, newIndex: number): void {
    if (index < 0 || newIndex < 0 || newIndex >= this.engineOrder.length || index === newIndex) {
      return;
    }
    const moved: string = this.engineOrder.splice(index, 1)[0];
    this.engineOrder.splice(newIndex, 0, moved);
    this.orderDirty = true;
  }

  // 松手：浮起复位 + 持久化（顺序有变化时）
  private endDrag(): void {
    const dragged: string = this.dragId;
    this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 400, 38) }, (): void => {
      this.dragId = '';
      this.offsetY = 0;
    });
    if (dragged !== '' && this.orderDirty) {
      this.orderDirty = false;
      Settings.setTransEngineOrder(this.engineOrder.join(','));
    }
  }

  // 全量刷新内存镜像（配置变更后触发 V1 状态刷新）
  private refreshState(): void {
    this.engineOrder = TranslationService.effectiveOrder();
    this.targetLang = Settings.getTransTargetLang();
  }

  // ---- 凭据编辑 ----

  // 点击引擎行：需密钥引擎弹出对应配置框，免密钥引擎提示无需配置
  private openEngineConfig(id: string): void {
    if (id === 'baidu') {
      this.editBaidu();
    } else if (id === 'youdao') {
      this.editYoudao();
    } else if (id === 'caiyun') {
      this.editCaiyun();
    } else if (id === 'tencent') {
      this.editTencent();
    } else if (id === 'volcano') {
      this.editVolcano();
    } else if (id === 'niutrans') {
      this.editNiutrans();
    } else {
      Util.toastRes(this.getUIContext(), $r('app.string.trans_status_free'));
    }
  }

  private editBaidu(): void {
    const dialog = new CustomDialogController({
      builder: CredentialsDialog({
        title: $r('app.string.trans_baidu'),
        usernamePlaceholder: $r('app.string.trans_baidu_appid'),
        passwordPlaceholder: $r('app.string.trans_baidu_key'),
        onConfirm: (appid: string, key: string): void => {
          Settings.setTransBaiduAppid(appid);
          Settings.setTransBaiduKey(key);
          this.refreshState();
        },
        onClose: (): void => {
          dialog.close();
        }
      }),
      autoCancel: true
    });
    dialog.open();
  }

  private editYoudao(): void {
    const dialog = new CustomDialogController({
      builder: CredentialsDialog({
        title: $r('app.string.trans_youdao'),
        usernamePlaceholder: $r('app.string.trans_youdao_key'),
        passwordPlaceholder: $r('app.string.trans_youdao_secret'),
        onConfirm: (appKey: string, secret: string): void => {
          Settings.setTransYoudaoKey(appKey);
          Settings.setTransYoudaoSecret(secret);
          this.refreshState();
        },
        onClose: (): void => {
          dialog.close();
        }
      }),
      autoCancel: true
    });
    dialog.open();
  }

  private editCaiyun(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.trans_caiyun_token'),
        placeholder: $r('app.string.trans_caiyun_token'),
        initialText: Settings.getTransCaiyunToken(),
        onConfirm: (text: string): void => {
          Settings.setTransCaiyunToken(text.trim());
          this.refreshState();
        },
        onClose: (): void => {
          dialog.close();
        }
      }),
      autoCancel: true
    });
    dialog.open();
  }

  private editTencent(): void {
    const dialog = new CustomDialogController({
      builder: CredentialsDialog({
        title: $r('app.string.trans_tencent'),
        usernamePlaceholder: $r('app.string.trans_tencent_secret_id'),
        passwordPlaceholder: $r('app.string.trans_tencent_secret_key'),
        onConfirm: (secretId: string, secretKey: string): void => {
          Settings.setTransTencentSecretId(secretId.trim());
          Settings.setTransTencentSecretKey(secretKey.trim());
          this.refreshState();
        },
        onClose: (): void => {
          dialog.close();
        }
      }),
      autoCancel: true
    });
    dialog.open();
  }

  private editVolcano(): void {
    const dialog = new CustomDialogController({
      builder: CredentialsDialog({
        title: $r('app.string.trans_volcano'),
        usernamePlaceholder: $r('app.string.trans_volcano_access_key'),
        passwordPlaceholder: $r('app.string.trans_volcano_secret_key'),
        onConfirm: (accessKey: string, secretKey: string): void => {
          Settings.setTransVolcanoAccessKey(accessKey.trim());
          Settings.setTransVolcanoSecretKey(secretKey.trim());
          this.refreshState();
        },
        onClose: (): void => {
          dialog.close();
        }
      }),
      autoCancel: true
    });
    dialog.open();
  }

  private editNiutrans(): void {
    const dialog = new CustomDialogController({
      builder: InputDialog({
        title: $r('app.string.trans_niutrans_apikey'),
        placeholder: $r('app.string.trans_niutrans_apikey'),
        initialText: Settings.getTransNiutransApikey(),
        onConfirm: (text: string): void => {
          Settings.setTransNiutransApikey(text.trim());
          this.refreshState();
        },
        onClose: (): void => {
          dialog.close();
        }
      }),
      autoCancel: true
    });
    dialog.open();
  }

  // ---- 连通性测试：按当前优先级链路翻译一句日语 ----

  private runTest(): void {
    if (this.testing) {
      return;
    }
    this.testing = true;
    const ui = this.getUIContext();
    TranslationService.translateText('こんにちは', 'ja', Settings.getTransTargetLang())
      .then((result: string) => {
        this.testing = false;
        if (result === '') {
          Util.toastRes(ui, $r('app.string.trans_test_fail'));
        } else {
          Util.toast(ui, result);
        }
      })
      .catch((_e: Error) => {
        this.testing = false;
        Util.toastRes(ui, $r('app.string.trans_test_fail'));
      });
  }
}

// 翻译设置路由壳（手机/平板窄屏 push 进入）
@Component
export struct TranslationPage {
  build() {
    NavGlassPage({ title: $r('app.string.trans_title') }) {
      Column() {
        TranslationContent()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }
}

// 系统路由表构建入口（router_map.json 注册）
@Builder
export function TranslationBuilder() {
  TranslationPage()
}
