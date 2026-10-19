/*
 * BtComponentInstaller — BT 组件（torrent HSP，deliveryWithInstall:false）
 * 按需安装封装（AppGallery 分发渠道，moduleInstallManager）。
 *
 * 仅可在前台 UIAbilityContext 下发起请求；下载/安装进度经
 * on('moduleInstallStatus') 推送，移动网络下由系统流量确认弹窗接管。
 */
import { moduleInstallManager } from '@kit.AppGalleryKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class BtComponentInstaller {
  private static currentTaskId: string = '';

  // 查询组件是否已安装。接口异常时 fail-open 返回 true：
  // 非 AGC 分发环境（侧载/调试）不该误弹安装引导，最终以
  // BtModule 动态 import 能否加载为准
  static isInstalled(): boolean {
    try {
      const info: moduleInstallManager.InstalledModule =
        moduleInstallManager.getInstalledModule('torrent');
      return info.installStatus === moduleInstallManager.InstallStatus.INSTALLED;
    } catch (e) {
      hilog.warn(0x0001, 'BtInstall', 'getInstalledModule failed: %{public}s', `${e}`);
      return true;
    }
  }

  // 发起按需下载安装；onProgress 回调 0-100 进度，安装完成 resolve，
  // 失败/被取消 reject。须在前台调用（RequestErrorCode.FOREGROUND_REQUIRED）
  static requestInstall(context: common.UIAbilityContext,
    onProgress: (progress: number) => void): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      let settled = false;
      const settleOk = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        BtComponentInstaller.currentTaskId = '';
        BtComponentInstaller.offStatus();
        resolve();
      };
      const settleFail = (reason: string): void => {
        if (settled) {
          return;
        }
        settled = true;
        BtComponentInstaller.currentTaskId = '';
        BtComponentInstaller.offStatus();
        reject(new Error(reason));
      };
      const onState = (state: moduleInstallManager.ModuleInstallSessionState): void => {
        if (state.taskId !== undefined && state.taskId !== '') {
          BtComponentInstaller.currentTaskId = state.taskId;
        }
        const total: number = state.totalSize ?? 0;
        const done: number = state.downloadedSize ?? 0;
        if (total > 0 && done >= 0) {
          // 上限 99：100 由安装成功时机给出，避免进度先于状态跳满
          const pct = Math.min(99, Math.floor(done * 100 / total));
          onProgress(pct);
        }
        if (state.code !== moduleInstallManager.RequestErrorCode.SUCCESS) {
          settleFail(`bt_install_code_${state.code}`);
          return;
        }
        const ts = state.taskStatus;
        if (ts === moduleInstallManager.TaskStatus.INSTALL_SUCCESSFUL) {
          onProgress(100);
          settleOk();
        } else if (ts === moduleInstallManager.TaskStatus.DOWNLOAD_FAILED ||
          ts === moduleInstallManager.TaskStatus.INSTALL_FAILED ||
          ts === moduleInstallManager.TaskStatus.CREATE_TASK_FAILED ||
          ts === moduleInstallManager.TaskStatus.HIGHER_VERSION_INSTALLED) {
          settleFail(`bt_install_status_${ts}`);
        }
      };
      try {
        moduleInstallManager.on('moduleInstallStatus', onState, 30 * 60);
      } catch (e) {
        reject(new Error(`bt_install_listen_failed: ${e}`));
        return;
      }
      try {
        const provider = new moduleInstallManager.ModuleInstallProvider();
        const request = provider.createModuleInstallRequest(context);
        const added: moduleInstallManager.ReturnCode = request.addModule('torrent');
        if (added !== moduleInstallManager.ReturnCode.SUCCESS) {
          settleFail(`bt_add_module_${added}`);
          return;
        }
        moduleInstallManager.fetchModules(request)
          .then((state: moduleInstallManager.ModuleInstallSessionState): void => {
            if (state.code === moduleInstallManager.RequestErrorCode.DOWNLOAD_WAIT_WIFI) {
              // 移动网络：拉起系统流量确认弹窗，用户确认后任务继续（进度走 on 回调）
              try {
                moduleInstallManager.showCellularDataConfirmation(context, state.taskId);
              } catch (e) {
                settleFail(`bt_cellular_confirm_failed: ${e}`);
              }
              return;
            }
            if (state.code !== moduleInstallManager.RequestErrorCode.SUCCESS) {
              settleFail(`bt_install_code_${state.code}`);
              return;
            }
            // 任务已存在/本地更高版本等非成功终态立即收尾，其余等待 on 推进
            if (state.taskStatus === moduleInstallManager.TaskStatus.INSTALL_SUCCESSFUL) {
              settleOk();
            } else if (state.taskStatus === moduleInstallManager.TaskStatus.HIGHER_VERSION_INSTALLED ||
              state.taskStatus === moduleInstallManager.TaskStatus.TASK_ALREADY_EXISTS) {
              settleFail(`bt_install_status_${state.taskStatus}`);
            }
          })
          .catch((e: BusinessError): void => {
            settleFail(`bt_fetch_failed: ${e.code} ${e.message}`);
          });
      } catch (e) {
        settleFail(`bt_fetch_throw: ${e}`);
      }
    });
  }

  // 取消进行中的安装任务（用户关闭下载中弹窗时调用）
  static cancelCurrent(): void {
    const taskId = BtComponentInstaller.currentTaskId;
    BtComponentInstaller.currentTaskId = '';
    if (taskId === '') {
      return;
    }
    try {
      moduleInstallManager.cancelTask(taskId);
    } catch (e) {
      hilog.warn(0x0001, 'BtInstall', 'cancelTask failed: %{public}s', `${e}`);
    }
  }

  private static offStatus(): void {
    try {
      moduleInstallManager.off('moduleInstallStatus');
    } catch (_e) {
    }
  }
}
