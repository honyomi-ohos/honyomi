import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WidgetUpdater, CardFormInfo } from './WidgetUpdater';

const DOMAIN = 0x0001;
const TAG = 'EntryFormAbility';

// 桌面卡片扩展：onAddForm 同步返回默认数据后异步补全；onUpdateForm 定时刷新；
// onRemoveForm 清理注册表。卡片数据构建与主动刷新逻辑由 WidgetUpdater 统一管理。
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params = want.parameters;
    let formId = '';
    let name = '';
    let wide = false;
    let mangaId = 0;
    if (params !== undefined) {
      const idVal = params[formInfo.FormParam.IDENTITY_KEY];
      if (typeof idVal === 'string') {
        formId = idVal;
      }
      const nameVal = params[formInfo.FormParam.NAME_KEY];
      if (typeof nameVal === 'string') {
        name = nameVal;
      }
      const dimVal = params[formInfo.FormParam.DIMENSION_KEY];
      if (dimVal !== undefined) {
        wide = Number(dimVal) === formInfo.FormDimension.Dimension_2_4;
      }
      // 漫画卡片：requestPublishForm 传入的 mangaId（系统可能不转发，由 pending 机制兜底）
      if (name === 'MangaCard') {
        const midVal = params['mangaId'];
        if (typeof midVal === 'number') {
          mangaId = midVal;
        }
      }
    }
    hilog.info(DOMAIN, TAG, 'onAddForm %{public}s name=%{public}s wide=%{public}s', formId, name, `${wide}`);

    const info = new CardFormInfo();
    info.formId = formId;
    info.name = name;
    info.wide = wide;
    info.mangaId = mangaId;
    if (name === 'MangaCard') {
      // 单链串行：mangaId 解析（pending / 书架内最近阅读回退）必须先于 saveForm
      WidgetUpdater.addMangaCard(this.context, info).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'addMangaCard failed: %{public}s', e.message);
      });
    } else {
      WidgetUpdater.saveForm(this.context, info).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'saveForm failed: %{public}s', e.message);
      });
      WidgetUpdater.refreshOne(this.context, info).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'refreshOne onAdd failed: %{public}s', e.message);
      });
    }

    // 同步返回：仅含 wide 布局标志，行数据由异步 updateForm 补全
    const record: Record<string, boolean> = { 'wide': wide };
    return formBindingData.createFormBindingData(record);
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm %{public}s', formId);
    WidgetUpdater.loadForms(this.context).then((forms: CardFormInfo[]) => {
      for (let i = 0; i < forms.length; i++) {
        if (forms[i].formId === formId) {
          WidgetUpdater.refreshOne(this.context, forms[i]);
          break;
        }
      }
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'onUpdateForm loadForms failed: %{public}s', e.message);
    });
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent %{public}s msg=%{public}s', formId, message);
    WidgetUpdater.loadForms(this.context).then((forms: CardFormInfo[]) => {
      for (let i = 0; i < forms.length; i++) {
        if (forms[i].formId === formId) {
          WidgetUpdater.refreshOne(this.context, forms[i]);
          break;
        }
      }
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'onFormEvent loadForms failed: %{public}s', e.message);
    });
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm %{public}s', formId);
    WidgetUpdater.removeForm(this.context, formId).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'onRemoveForm failed: %{public}s', e.message);
    });
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
