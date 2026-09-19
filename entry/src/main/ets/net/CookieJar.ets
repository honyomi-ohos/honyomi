import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'CookieJar';

interface PersistShape {
  domains?: Record<string, Record<string, string>>;
}

// 域名级 Cookie 存储：自动回收响应 Set-Cookie 并持久化，请求时自动附带
// （插件 $.http、图片管线、下载服务全部经此受益；cf_clearance 亦存放于此）
export class CookieJar {
  private static jar: Map<string, Record<string, string>> = new Map();
  private static filePath: string = '';
  private static saveTimer: number = -1;

  static init(context: common.UIAbilityContext): void {
    CookieJar.filePath = `${context.filesDir}/cookies.json`;
    try {
      if (fs.accessSync(CookieJar.filePath)) {
        const raw = JSON.parse(fs.readTextSync(CookieJar.filePath)) as PersistShape;
        const domains = raw.domains;
        if (domains !== undefined) {
          const keys = Object.keys(domains);
          for (const d of keys) {
            CookieJar.jar.set(d, domains[d]);
          }
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'load failed: %{public}s', (e as Error).message);
    }
  }

  // 提取 url 的 host（小写、去端口）
  static hostOf(url: string): string {
    const i = url.indexOf('://');
    if (i < 0) {
      return '';
    }
    let rest = url.substring(i + 3);
    const at = rest.indexOf('@');
    if (at >= 0) {
      rest = rest.substring(at + 1);
    }
    let end = rest.length;
    const slash = rest.indexOf('/');
    if (slash >= 0 && slash < end) {
      end = slash;
    }
    const q = rest.indexOf('?');
    if (q >= 0 && q < end) {
      end = q;
    }
    const hash = rest.indexOf('#');
    if (hash >= 0 && hash < end) {
      end = hash;
    }
    let host = rest.substring(0, end).toLowerCase();
    const colon = host.indexOf(':');
    if (colon >= 0) {
      host = host.substring(0, colon);
    }
    return host;
  }

  // 汇总适用于 url 的 Cookie 请求头（host 精确匹配或父域后缀匹配）
  static headerFor(url: string): string {
    const host = CookieJar.hostOf(url);
    if (host === '') {
      return '';
    }
    const parts: string[] = [];
    CookieJar.jar.forEach((cookies: Record<string, string>, domain: string) => {
      if (host === domain || host.endsWith(`.${domain}`)) {
        const names = Object.keys(cookies);
        for (const name of names) {
          parts.push(`${name}=${cookies[name]}`);
        }
      }
    });
    return parts.join('; ');
  }

  // 解析 OHOS http 响应头对象中的 Set-Cookie（可能为 string 或 string[]）
  static storeFromResponse(url: string, header: Object): void {
    const h = header as Record<string, Object>;
    const keys = Object.keys(h);
    for (const k of keys) {
      if (k.toLowerCase() !== 'set-cookie') {
        continue;
      }
      const v = h[k];
      if (typeof v === 'string') {
        CookieJar.storeOne(url, v);
      } else if (Array.isArray(v)) {
        const list = v as string[];
        for (const s of list) {
          CookieJar.storeOne(url, s);
        }
      }
    }
  }

  // 导入 ArkWeb cookie 字符串（"a=1; b=2" 形态，如 CF 验证页收割）
  static importCookieString(url: string, cookieStr: string): void {
    const host = CookieJar.hostOf(url);
    if (host === '' || cookieStr === '') {
      return;
    }
    const parts = cookieStr.split(';');
    for (const part of parts) {
      const p = part.trim();
      const eq = p.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      CookieJar.put(host, p.substring(0, eq).trim(), p.substring(eq + 1).trim());
    }
  }

  // 解析并保存单个 Set-Cookie 值（识别 Domain / Max-Age 属性）
  static storeOne(url: string, setCookie: string): void {
    const segments = setCookie.split(';');
    const first = segments[0].trim();
    const eq = first.indexOf('=');
    if (eq <= 0) {
      return;
    }
    const name = first.substring(0, eq).trim();
    const value = first.substring(eq + 1).trim();
    if (name === '') {
      return;
    }
    let domain = CookieJar.hostOf(url);
    let expired = false;
    for (let i = 1; i < segments.length; i++) {
      const seg = segments[i].trim();
      const lower = seg.toLowerCase();
      if (lower.indexOf('domain=') === 0) {
        domain = seg.substring(7).trim().toLowerCase();
        if (domain.startsWith('.')) {
          domain = domain.substring(1);
        }
      } else if (lower.indexOf('max-age=') === 0 &&
        parseInt(seg.substring(8).trim(), 10) <= 0) {
        expired = true;
      }
    }
    if (domain === '') {
      return;
    }
    if (expired) {
      CookieJar.remove(domain, name);
      return;
    }
    CookieJar.put(domain, name, value);
  }

  static clear(): void {
    CookieJar.jar.clear();
    CookieJar.save();
  }

  // ---------------- 内部实现 ----------------

  private static put(domain: string, name: string, value: string): void {
    let cookies = CookieJar.jar.get(domain);
    if (cookies === undefined) {
      const fresh: Record<string, string> = {};
      CookieJar.jar.set(domain, fresh);
      cookies = fresh;
    }
    cookies[name] = value;
    CookieJar.scheduleSave();
  }

  private static remove(domain: string, name: string): void {
    const cookies = CookieJar.jar.get(domain);
    if (cookies === undefined) {
      return;
    }
    const kept: Record<string, string> = {};
    const names = Object.keys(cookies);
    for (const n of names) {
      if (n !== name) {
        kept[n] = cookies[n];
      }
    }
    if (Object.keys(kept).length === 0) {
      CookieJar.jar.delete(domain);
    } else {
      CookieJar.jar.set(domain, kept);
    }
    CookieJar.scheduleSave();
  }

  private static scheduleSave(): void {
    if (CookieJar.saveTimer >= 0) {
      clearTimeout(CookieJar.saveTimer);
    }
    CookieJar.saveTimer = setTimeout(() => {
      CookieJar.saveTimer = -1;
      CookieJar.save();
    }, 500);
  }

  private static save(): void {
    if (CookieJar.filePath === '') {
      return;
    }
    try {
      const domains: Record<string, Record<string, string>> = {};
      CookieJar.jar.forEach((cookies: Record<string, string>, domain: string) => {
        domains[domain] = cookies;
      });
      const shape: PersistShape = { domains: domains };
      const file = fs.openSync(CookieJar.filePath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(shape));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'save failed: %{public}s', (e as Error).message);
    }
  }
}
