import { harmonyShare, systemShare } from '@kit.ShareKit';
import { serviceInteraction } from '@kit.ServiceCollaborationKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ContinueSession } from './ContinueSession';
import { AppKeys } from './AppKeys';

const DOMAIN = 0x0001;
const TAG = 'KnockShare';

// 碰一碰对端推送的消息体（本应用自有格式，双端约定一致）
interface KnockMessage {
  target: string;
  contentType?: string;
  sourceKey?: string;
  mangaUrl?: string;
  chapterUrl?: string;
  page?: number;
  title?: string;
  chapterName?: string;
}

// 碰一碰双通道（均注册在主页 Index，随其生命周期注册/注销）：
// 1) harmonyShare 'knockShare'：华为分享"碰一碰"事件，把当前内容以 App Linking
//    分享到对端（对端已装应用经域名校验直达对应内容，未装走浏览器/应用市场）
// 2) serviceInteraction：双端均打开应用时的碰一碰建链，把当前会话 JSON 直接
//    推到对端，对端经 cardAction 通道续读（需 ohos.permission.KNOCK_COLLABORATION）
export class KnockShare {
  private static knockListening: boolean = false;
  private static serviceListening: boolean = false;
  private static serviceConfig: serviceInteraction.CollaborationConfig | undefined = undefined;
  private static serviceCallbacks: serviceInteraction.ServiceInteractionCallback | undefined = undefined;

  static register(windowId: number): void {
    KnockShare.registerKnock();
    KnockShare.registerServiceInteraction(windowId);
  }

  static unregister(): void {
    KnockShare.unregisterKnock();
    KnockShare.unregisterServiceInteraction();
  }

  // ---- 通道一：华为分享碰一碰（App Linking 链接分享）----

  private static registerKnock(): void {
    if (KnockShare.knockListening || !canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      return;
    }
    try {
      harmonyShare.on('knockShare', (target: harmonyShare.SharableTarget): void => {
        KnockShare.onKnock(target);
      });
      KnockShare.knockListening = true;
      hilog.info(DOMAIN, TAG, 'knockShare registered');
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'knockShare register failed: %{public}d %{public}s', err.code, err.message);
    }
  }

  private static unregisterKnock(): void {
    if (!KnockShare.knockListening) {
      return;
    }
    try {
      harmonyShare.off('knockShare');
      KnockShare.knockListening = false;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'knockShare unregister failed: %{public}d %{public}s', err.code, err.message);
    }
  }

  // 碰一碰事件回调：3 秒内必须发起分享，无活动会话时回退应用主页链接
  private static onKnock(target: harmonyShare.SharableTarget): void {
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
        content: ContinueSession.toAppLink(),
        title: ContinueSession.titleText(),
        description: ContinueSession.chapterNameText()
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      target.share(data).then((): void => {
        hilog.info(DOMAIN, TAG, 'knock share sent');
      }).catch((e: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'knock share failed: %{public}d %{public}s', e.code, e.message);
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'knock share exception: %{public}d %{public}s', err.code, err.message);
    }
  }

  // ---- 通道二：应用间碰一碰建链（serviceInteraction）----

  private static registerServiceInteraction(windowId: number): void {
    if (KnockShare.serviceListening || !canIUse('SystemCapability.Collaboration.Connection')) {
      return;
    }
    try {
      const config: serviceInteraction.CollaborationConfig = {
        triggerType: serviceInteraction.TriggerType.KNOCK,
        windowId: windowId,
        appLinking: ContinueSession.toAppLink(),
        timeOut: 20
      };
      const callbacks: serviceInteraction.ServiceInteractionCallback = {
        onDeviceConnect: (connection: serviceInteraction.Connection): void => {
          KnockShare.onDeviceConnect(connection);
        },
        onDeviceDisconnect: (connection: serviceInteraction.Connection, retCode: number): void => {
          hilog.info(DOMAIN, TAG, 'service disconnected: %{public}d %{public}d', connection.connectId, retCode);
        },
        onMessageReceive: (connection: serviceInteraction.Connection, data: ArrayBuffer): void => {
          KnockShare.onMessageReceive(data);
        },
        onConnectFail: (retCode: number): void => {
          hilog.warn(DOMAIN, TAG, 'service connect failed: %{public}d', retCode);
        }
      };
      serviceInteraction.onServiceInteraction(config, callbacks);
      KnockShare.serviceConfig = config;
      KnockShare.serviceCallbacks = callbacks;
      KnockShare.serviceListening = true;
      hilog.info(DOMAIN, TAG, 'serviceInteraction registered, window=%{public}d', windowId);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'serviceInteraction register failed: %{public}d %{public}s', err.code, err.message);
    }
  }

  private static unregisterServiceInteraction(): void {
    if (!KnockShare.serviceListening) {
      return;
    }
    try {
      if (KnockShare.serviceConfig !== undefined && KnockShare.serviceCallbacks !== undefined) {
        serviceInteraction.offServiceInteraction(KnockShare.serviceConfig, KnockShare.serviceCallbacks);
      }
      KnockShare.serviceListening = false;
      KnockShare.serviceConfig = undefined;
      KnockShare.serviceCallbacks = undefined;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'serviceInteraction unregister failed: %{public}d %{public}s', err.code, err.message);
    }
  }

  // 建链成功：把当前会话 JSON 推到对端后断开（一次性推送，无需保持连接）
  private static onDeviceConnect(connection: serviceInteraction.Connection): void {
    const json = ContinueSession.toJson();
    if (json === '') {
      connection.disconnect().catch((e: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'disconnect failed: %{public}d %{public}s', e.code, e.message);
      });
      return;
    }
    try {
      const bytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(json);
      const ab: ArrayBuffer = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(ab).set(bytes);
      connection.sendMessage(ab).then((): void => {
        hilog.info(DOMAIN, TAG, 'session pushed');
        connection.disconnect().catch((e: BusinessError): void => {
          hilog.warn(DOMAIN, TAG, 'disconnect failed: %{public}d %{public}s', e.code, e.message);
        });
      }).catch((e: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'send session failed: %{public}d %{public}s', e.code, e.message);
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'send session exception: %{public}d %{public}s', err.code, err.message);
    }
  }

  // 收到对端推送：解析会话 JSON，经 cardAction 通道由 Index 解析定位续读
  private static onMessageReceive(data: ArrayBuffer): void {
    try {
      const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data));
      const raw = JSON.parse(text) as KnockMessage;
      if (raw === undefined || raw === null || raw.target !== 'continue') {
        return;
      }
      const sourceKey = typeof raw.sourceKey === 'string' ? raw.sourceKey : '';
      const mangaUrl = typeof raw.mangaUrl === 'string' ? raw.mangaUrl : '';
      if (sourceKey === '' || mangaUrl === '') {
        return;
      }
      const pageRaw = typeof raw.page === 'number' && Number.isFinite(raw.page) ? Math.floor(raw.page) : 0;
      const payload: Record<string, string | number> = {
        'target': 'continue',
        'contentType': typeof raw.contentType === 'string' ? raw.contentType : '',
        'sourceKey': sourceKey,
        'mangaUrl': mangaUrl,
        'chapterUrl': typeof raw.chapterUrl === 'string' ? raw.chapterUrl : '',
        'page': pageRaw,
        'title': typeof raw.title === 'string' ? raw.title : '',
        'chapterName': typeof raw.chapterName === 'string' ? raw.chapterName : ''
      };
      AppStorage.setOrCreate(AppKeys.CARD_ACTION, JSON.stringify(payload));
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'receive session failed: %{public}d %{public}s', err.code, err.message);
    }
  }
}
