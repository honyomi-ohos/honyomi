import { connection, http, socket } from '@kit.NetworkKit';
import { Settings } from '../common/Settings';
import { Log } from '../common/Log';

const TAG = 'Doh';

// DoH 供应商（RFC 8484 标准 wire-format 端点，对齐 Mihon PREF_DOH 列表）
export interface DohProvider {
  id: string;
  label: string;
  url: string;

  // true = 走 DNS-over-HTTPS JSON API（Google resolve 风格 ?name=&type=A）。
  // doh.pub 实测 wire API 应答被上游污染，JSON API 返回干净结果，故 dnspod 走 JSON
  json?: boolean;
}

// DNS 应答解析结果：IPv4 列表 + 最小 TTL（秒）
interface DohAnswer {
  ips: string[];
  ttl: number;
}

// JSON API 原始应答模型（JSON.parse 后一次性转换）
interface DohJsonAnswer {
  Status?: number;
  Answer?: DohJsonRecord[];
}

interface DohJsonRecord {
  type?: number;
  TTL?: number;
  data?: string;
}

// host → 已注入 netstack 的映射缓存
interface DohCacheEntry {
  ips: string[];
  expireAt: number;
  pin: boolean;
}

// DNS over HTTPS 解析器：
// - 开启后对每个新 host 先经所选供应商做 RFC 8484 查询，再以
//   connection.addCustomDnsRule 注入应用 netstack（应用内所有请求生效，
//   含下载与系统 Image 网络栈）
// - 查询走独立裸 http 通道（不经 Http/CookieJar/UA 管线，天然免递归）
// - 解析失败 fail-open：不注入规则，回落系统 DNS，绝不阻断业务请求
// - 结果缓存至 TTL 过期（钳制 60s - 1h），并发去重
// - 应答经 GFW 假 IP 池过滤 + TCP 探测验证，只注入真实可连的 IP，
//   防止污染应答把请求引向假 IP；被拒后立即重查（上游注入为竞态窗口，
//   重查即可能拿到干净应答），连续被拒则短负缓存后 fail-open
// - 插件 pin（$.dns.set）优先于 DoH：pin 存活期间 DoH 永不覆盖
// - 供应商网络故障（超时/被 RST）后 60s 内直接 fail-open，避免每请求烧超时
export class Doh {
  // 供应商清单（顺序即设置页展示顺序）
  static readonly PROVIDERS: DohProvider[] = [
    { id: 'cloudflare', label: 'Cloudflare', url: 'https://cloudflare-dns.com/dns-query' },
    { id: 'google', label: 'Google', url: 'https://dns.google/dns-query' },
    { id: 'adguard', label: 'AdGuard', url: 'https://dns.adguard-dns.com/dns-query' },
    { id: 'quad9', label: 'Quad9', url: 'https://dns.quad9.net/dns-query' },
    { id: 'alidns', label: 'AliDNS', url: 'https://dns.alidns.com/dns-query' },
    {
      id: 'dnspod',
      label: 'DNSPod',
      url: 'https://doh.pub/dns-query',
      json: true
    },
    { id: '360', label: '360', url: 'https://doh.360.cn/dns-query' },
    { id: 'quad101', label: 'Quad 101', url: 'https://dns.twnic.tw/dns-query' },
    { id: 'mullvad', label: 'Mullvad', url: 'https://dns.mullvad.net/dns-query' },
    { id: 'controld', label: 'Control D', url: 'https://freedom.dns.controld.com/dns-query' },
    { id: 'njalla', label: 'Njalla', url: 'https://dns.njal.la/dns-query' },
    { id: 'shecan', label: 'Shecan', url: 'https://free.shecan.ir/dns-query' },
  ];
  // 插件显式 pin（$.dns.set）的有效期：netstack 规则进程内常驻，
  // 缓存 pin 只为拦住 DoH prepare 的重复解析/覆盖，取一个足够长的会话级 TTL
  private static readonly PIN_TTL_MS: number = 24 * 3600 * 1000;
  private static cache: Map<string, DohCacheEntry> = new Map();
  private static inflight: Map<string, Promise<void>> = new Map();
  private static querySeq: number = 1;
  private static providerFailedUntil: number = 0;
  // 供应商网络故障退避窗口
  private static readonly PROVIDER_BACKOFF_MS: number = 60 * 1000;
  // 应答 IP 真实性探测参数（真 IP 秒连，假 IP 黑洞/RST 被拒）
  private static readonly PROBE_PORT: number = 443;
  private static readonly PROBE_TIMEOUT_MS: number = 900;
  // 应答被拒后的立即重查次数（GFW 对上游递归的注入为竞态，重查即可能干净）
  private static readonly RESOLVE_ATTEMPTS: number = 3;
  // 连续被拒后的短负缓存：窗口内 fail-open 不再烧查询/探测
  private static readonly NEG_TTL_MS: number = 15 * 1000;
  // GFW 污染假 IP 段（Facebook/Twitter 段 + 经典单 IP）。命中即弃用；
  // 未命中仍经 TCP 探测验证，此表只做黑名单快速路径
  private static readonly FAKE_RANGES: number[][] = [
    [0x1F0D1800, 0xFFFFF800], // 31.13.24.0/21
    [0x1F0D4000, 0xFFC00000], // 31.13.64.0/18
    [0x42DC9000, 0xFFFFF000], // 66.220.144.0/20
    [0x453FB000, 0xFFFFF000], // 69.63.176.0/20
    [0x45ABE000, 0xFFFFE000], // 69.171.224.0/19
    [0x4A774C00, 0xFFFFFC00], // 74.119.76.0/22
    [0x66846000, 0xFFFFF000], // 102.132.96.0/20
    [0x67046000, 0xFFFFFC00], // 103.4.96.0/22
    [0x9DF00000, 0xFFFF0000], // 157.240.0.0/16
    [0xADFC4000, 0xFFC00000], // 173.252.64.0/18
    [0xCC0F1400, 0xFFFFFC00], // 204.15.20.0/22
    [0xC73B9400, 0xFFFFFC00], // 199.59.148.0/22
    [0x0807C62D, 0xFFFFFFFF], // 8.7.198.45
    [0x2E52AE44, 0xFFFFFFFF], // 46.82.174.68
    [0x3B1803AD, 0xFFFFFFFF], // 59.24.3.173
    [0x5D2E0859, 0xFFFFFFFF], // 93.46.8.89
    [0xCB620741, 0xFFFFFFFF], // 203.98.7.65
    [0xF3B9BB27, 0xFFFFFFFF],// 243.185.187.39
  ];

  // 当前生效供应商（设置未开启时 undefined）
  static currentProvider(): DohProvider | undefined {
    const id: string = Settings.getDohProvider();
    if (id === '') {
      return undefined;
    }
    return Doh.providerOf(id);
  }

  static providerOf(id: string): DohProvider | undefined {
    for (const p of Doh.PROVIDERS) {
      if (p.id === id) {
        return p;
      }
    }
    return undefined;
  }

  // 请求前调用：确保 host 的 DoH 映射已注入（失败静默回落系统 DNS）
  static async prepare(url: string): Promise<void> {
    const provider = Doh.currentProvider();
    if (provider === undefined) {
      return;
    }
    const host = Doh.hostOf(url);
    if (host === '' || Doh.isIpLiteral(host)) {
      return;
    }
    const now = Date.now();
    const hit = Doh.cache.get(host);
    if (hit !== undefined && (hit.pin || hit.expireAt > now)) {
      return;
    }
    if (Doh.providerFailedUntil > now) {
      return;
    }
    const pending = Doh.inflight.get(host);
    if (pending !== undefined) {
      await pending;
      return;
    }
    const job = Doh.resolveAndRegister(host, provider).then((): void => {
      Doh.inflight.delete(host);
    }).catch((): void => {
      Doh.inflight.delete(host);
    });
    Doh.inflight.set(host, job);
    await job;
  }

  // 关闭/切换供应商时清空全部自定义规则与缓存（规则仅进程内有效，重启即失）
  static reset(): void {
    Doh.cache.clear();
    Doh.providerFailedUntil = 0;
    try {
      connection.clearCustomDnsRules();
    } catch (e) {
      Log.debug(TAG, `clearCustomDnsRules failed: ${e}`);
    }
  }

  // 插件显式 DNS 直连（$.dns.set / NativeHttpBridge dnsSet 消息）：
  // 注入 netstack 直连规则（应用内全部请求生效），并写入长 TTL 缓存 pin，
  // 防止开启 DoH 时 prepare 用 DoH 应答覆盖插件指定的入口 IP。
  // host/ips 已由调用方校验（域名非 IP 字面量 / 1..8 个 IPv4）。
  static async pin(host: string, ips: string[]): Promise<void> {
    try {
      await connection.addCustomDnsRule(host, ips);
    } catch (e) {
const err = e as Error;
      throw err;
    }
    const entry: DohCacheEntry = { ips: ips, expireAt: Date.now() + Doh.PIN_TTL_MS, pin: true };
    Doh.cache.set(host, entry);
    Log.debug(TAG, `pin ${host} -> ${ips.join(',')}`);
  }

  private static async resolveAndRegister(host: string, provider: DohProvider): Promise<void> {
    let answer: DohAnswer | undefined;
    let validated: string[] = [];
    let ttl = 60;
    for (let attempt = 1; attempt <= Doh.RESOLVE_ATTEMPTS; attempt++) {
      try {
        answer = await Doh.resolve(host, provider);
      } catch (e) {
        // 供应商网络故障（连接超时/被 RST 等）：60s 内 fail-open，避免每请求烧超时
        Doh.providerFailedUntil = Date.now() + Doh.PROVIDER_BACKOFF_MS;
        Log.warn(TAG,
          `provider ${provider.id} unreachable, backoff ${Doh.PROVIDER_BACKOFF_MS / 1000}s, fail-open: ${e}`);
        return;
      }
      if (answer === undefined || answer.ips.length === 0) {
        Log.warn(TAG, `resolve ${host} via ${provider.id} got no answer, fail-open`);
        return;
      }
      // pin 保护：解析期间插件已显式 pin 该 host，DoH 应答不覆盖插件指定 IP
      const pinned = Doh.cache.get(host);
      if (pinned !== undefined && pinned.pin) {
        Log.debug(TAG, `skip ${host}: pinned by plugin`);
        return;
      }
      // GFW 假 IP 池快速过滤 + TCP 探测验证，只注入真实可连的 IP
      const candidates: string[] = [];
      for (const ip of answer.ips) {
        if (!Doh.isKnownFakeIp(ip)) {
          candidates.push(ip);
        }
      }
      validated = await Doh.probeIps(candidates);
      if (validated.length > 0) {
        ttl = answer.ttl;
        break;
      }
      Log.warn(TAG, `answer for ${host} rejected (poisoned/unreachable): ${answer.ips.join(
        ',')} via ${provider.id} (attempt ${attempt}/${Doh.RESOLVE_ATTEMPTS})`);
    }
    if (validated.length === 0) {
      // 连续被拒：短负缓存后 fail-open（回落系统 DNS），窗口过后自动重试
      const negEntry: DohCacheEntry = { ips: [], expireAt: Date.now() + Doh.NEG_TTL_MS, pin: false };
      Doh.cache.set(host, negEntry);
      return;
    }
    // 注入前再查一次 pin：探测期间插件 pin 落地时不覆盖
    const pinnedFinal = Doh.cache.get(host);
    if (pinnedFinal !== undefined && pinnedFinal.pin) {
      Log.debug(TAG, `skip ${host}: pinned by plugin (late)`);
      return;
    }
    try {
      await connection.addCustomDnsRule(host, validated);
    } catch (e) {
const err = e as Error;
      throw err;
    }
    const ttlMs: number = Math.min(Math.max(ttl, 60), 3600) * 1000;
    const entry: DohCacheEntry = { ips: validated, expireAt: Date.now() + ttlMs, pin: false };
    Doh.cache.set(host, entry);
    Log.debug(TAG, `${host} -> ${validated.join(',')} via ${provider.id} ttl=${ttl}`);
  }

  // 并行探测候选 IP 的 TCP 可达性，返回真实可连的子集（空数组 = 全部被拒）
  private static async probeIps(ips: string[]): Promise<string[]> {
    const tasks: Promise<boolean>[] = [];
    for (const ip of ips) {
      tasks.push(Doh.probeIp(ip));
    }
    const results: boolean[] = await Promise.all(tasks);
    const ok: string[] = [];
    for (let i = 0; i < ips.length; i++) {
      if (results[i]) {
        ok.push(ips[i]);
      }
    }
    return ok;
  }

  private static async probeIp(ip: string): Promise<boolean> {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    try {
      await tcp.connect({ address: { address: ip, port: Doh.PROBE_PORT }, timeout: Doh.PROBE_TIMEOUT_MS });
      return true;
    } catch (e) {
      return false;
    } finally {
      tcp.close().catch((): void => {
      });
    }
  }

  // RFC 8484：POST application/dns-message（单问题 A 查询）
  private static async resolve(host: string, provider: DohProvider): Promise<DohAnswer | undefined> {
    if (provider.json === true) {
      return Doh.resolveJson(host, provider);
    }
    const id = (Doh.querySeq++) & 0xffff;
    const query = Doh.buildQuery(id, host);
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/dns-message',
          'Accept': 'application/dns-message'
        },
        extraData: query.buffer,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 3000,
        readTimeout: 5000,
      };
      const resp = await client.request(provider.url, options);
      if (resp.responseCode < 200 || resp.responseCode >= 300 || typeof resp.result !== 'object') {
        return undefined;
      }
      return Doh.parseAnswer(new Uint8Array(resp.result as ArrayBuffer));
    } catch (e) {
const err = e as Error;
      throw err;
    } finally {
      client.destroy();
    }
  }

  // JSON API 查询：GET {url}?name={host}&type=A（accept: application/dns-json）
  private static async resolveJson(host: string, provider: DohProvider): Promise<DohAnswer | undefined> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/dns-json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 3000,
        readTimeout: 5000,
      };
      const resp = await client.request(`${provider.url}?name=${host}&type=A`, options);
      if (resp.responseCode < 200 || resp.responseCode >= 300 || typeof resp.result !== 'string') {
        return undefined;
      }
      const raw = JSON.parse(resp.result) as DohJsonAnswer;
      if (raw.Status !== 0 || raw.Answer === undefined || raw.Answer.length === 0) {
        return undefined;
      }
      const ips: string[] = [];
      let minTtl = 3600;
      for (const rec of raw.Answer) {
        if (rec.type === 1 && rec.data !== undefined && Doh.ipToInt(rec.data) >= 0) {
          ips.push(rec.data);
          if (rec.TTL !== undefined && rec.TTL > 0 && rec.TTL < minTtl) {
            minTtl = rec.TTL;
          }
        }
      }
      const answer: DohAnswer = { ips: ips, ttl: minTtl };
      return answer;
    } catch (e) {
const err = e as Error;
      throw err;
    } finally {
      client.destroy();
    }
  }

  // DNS 报文构造：12 字节头 + QNAME + QTYPE(A)/QCLASS(IN)
  private static buildQuery(id: number, host: string): Uint8Array {
    const labels: string[] = host.split('.');
    let qnameLen = 1;
    for (const label of labels) {
      qnameLen += label.length + 1;
    }
    const buf = new ArrayBuffer(12 + qnameLen + 4);
    const view = new Uint8Array(buf);
    view[0] = (id >>> 8) & 0xff;
    view[1] = id & 0xff;
    view[2] = 0x01; // RD
    view[3] = 0x00;
    view[5] = 1; // QDCOUNT = 1
    let off = 12;
    for (const label of labels) {
      view[off] = label.length;
      off++;
      for (let i = 0; i < label.length; i++) {
        view[off] = label.charCodeAt(i) & 0xff;
        off++;
      }
    }
    view[off] = 0; // 根标签
    off++;
    view[off] = 0;
    view[off + 1] = 1; // QTYPE = A
    view[off + 2] = 0;
    view[off + 3] = 1; // QCLASS = IN
    return view;
  }

  // 应答解析：跳过问题区，遍历应答区取 A 记录 IPv4 与最小 TTL
  private static parseAnswer(msg: Uint8Array): DohAnswer | undefined {
    if (msg.length < 12) {
      return undefined;
    }
    const qdcount = (msg[4] << 8) | msg[5];
    const ancount = (msg[6] << 8) | msg[7];
    let off = 12;
    for (let i = 0; i < qdcount && off < msg.length; i++) {
      off = Doh.skipName(msg, off);
      if (off < 0 || off + 4 > msg.length) {
        return undefined;
      }
      off += 4; // QTYPE + QCLASS
    }
    const ips: string[] = [];
    let minTtl = 3600;
    for (let i = 0; i < ancount && off < msg.length; i++) {
      off = Doh.skipName(msg, off);
      if (off < 0 || off + 10 > msg.length) {
        break;
      }
      const type = (msg[off] << 8) | msg[off + 1];
      const ttl = Doh.readU32(msg, off + 4);
      const rdlength = (msg[off + 8] << 8) | msg[off + 9];
      off += 10;
      if (off + rdlength > msg.length) {
        break;
      }
      if (type === 1 && rdlength === 4) {
        ips.push(`${msg[off]}.${msg[off + 1]}.${msg[off + 2]}.${msg[off + 3]}`);
        if (ttl > 0 && ttl < minTtl) {
          minTtl = ttl;
        }
      }
      off += rdlength;
    }
    const answer: DohAnswer = { ips: ips, ttl: minTtl };
    return answer;
  }

  // 跳过 NAME 字段：压缩指针占 2 字节；标签序列以 0 结束。返回新偏移，越界 -1
  private static skipName(msg: Uint8Array, off: number): number {
    let p = off;
    while (p < msg.length) {
      const len = msg[p];
      if ((len & 0xc0) === 0xc0) {
        return p + 2;
      }
      if (len === 0) {
        return p + 1;
      }
      p += len + 1;
    }
    return -1;
  }

  private static readU32(msg: Uint8Array, off: number): number {
    return ((msg[off] << 24) | (msg[off + 1] << 16) | (msg[off + 2] << 8) | msg[off + 3]) >>> 0;
  }

  // 点分 IPv4 → 无符号整数；非法返回 -1
  private static ipToInt(ip: string): number {
    const parts: string[] = ip.split('.');
    if (parts.length !== 4) {
      return -1;
    }
    let v: number = 0;
    for (const part of parts) {
      const n: number = parseInt(part, 10);
      if (isNaN(n) || n < 0 || n > 255) {
        return -1;
      }
      v = v * 256 + n;
    }
    return v >>> 0;
  }

  // 是否命中 GFW 假 IP 段
  private static isKnownFakeIp(ip: string): boolean {
    const v = Doh.ipToInt(ip);
    if (v < 0) {
      return false;
    }
    for (const r of Doh.FAKE_RANGES) {
      if (((v & r[1]) >>> 0) === r[0]) {
        return true;
      }
    }
    return false;
  }

  // 从 URL 提取主机名（剥离协议/端口/路径/凭据）
  private static hostOf(url: string): string {
    let s = url;
    if (s.indexOf('https://') === 0) {
      s = s.substring(8);
    } else if (s.indexOf('http://') === 0) {
      s = s.substring(7);
    } else {
      return '';
    }
    const slash = s.indexOf('/');
    if (slash >= 0) {
      s = s.substring(0, slash);
    }
    const colon = s.indexOf(':');
    if (colon >= 0) {
      s = s.substring(0, colon);
    }
    const at = s.indexOf('@');
    if (at >= 0) {
      s = s.substring(at + 1);
    }
    return s.toLowerCase();
  }

  // 纯数字点分（IPv4 字面量）无需 DoH 解析
  private static isIpLiteral(host: string): boolean {
    if (host.indexOf(':') >= 0) {
      return true;
    }
    for (let i = 0; i < host.length; i++) {
      const c = host.charAt(i);
      if (c !== '.' && (c < '0' || c > '9')) {
        return false;
      }
    }
    return host.length > 0;
  }
}
