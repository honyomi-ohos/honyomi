/*
 * Cloudflare 盾页检测（Http 与 NativeHttpBridge 共用的统一实现）。
 * 策略（以 NativeHttpBridge 完整版为准）：
 *   - 状态码 401/403/503 视为可疑
 *   - cf-mitigated: challenge 响应头 → 挑战
 *   - 响应体含盾页特征文案（challenge-platform / Just a moment）→ 挑战
 */
export class CfChallenge {
  /** 响应头是否携带 cf-mitigated: challenge */
  static isCfMitigated(headers: Object): boolean {
    const raw = headers as Record<string, Object>;
    const keys = Object.keys(raw);
    for (const key of keys) {
      if (key.toLowerCase() === 'cf-mitigated') {
        const value = raw[key];
        if (typeof value === 'string' && (value as string).toLowerCase() === 'challenge') {
          return true;
        }
      }
    }
    return false;
  }

  /**
   * 是否为 CF 挑战响应。
   * @param status HTTP 状态码
   * @param body 已解码响应体（不可用时传 ''）
   * @param headers 响应头对象
   */
  static isCfChallenge(status: number, body: string, headers: Object): boolean {
    if (status !== 401 && status !== 403 && status !== 503) {
      return false;
    }
    if (CfChallenge.isCfMitigated(headers)) {
      return true;
    }
    return body !== '' && (body.indexOf('challenge-platform') >= 0 || body.indexOf('Just a moment') >= 0);
  }
}
