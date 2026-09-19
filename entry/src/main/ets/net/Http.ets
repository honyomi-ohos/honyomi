import { http } from '@kit.NetworkKit';

// HTTP 客户端封装（对齐 Mihon NetworkHelper 的最小集）
export class Http {
  static async get(url: string, headers: Record<string, string> | undefined): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers !== undefined ? headers : Http.defaultHeaders(),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000,
      };
      const resp: http.HttpResponse = await client.request(url, options);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}: ${url}`);
      }
      return resp.result as string;
    } finally {
      client.destroy();
    }
  }

  static async post(url: string, body: string, headers: Record<string, string> | undefined): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const merged: Record<string, string> = Http.defaultHeaders();
      if (headers !== undefined) {
        const keys = Object.keys(headers);
        for (const k of keys) {
          merged[k] = headers[k];
        }
      }
      merged['Content-Type'] = 'application/json';
      merged['Accept'] = 'application/json';
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: merged,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000,
      };
      const resp: http.HttpResponse = await client.request(url, options);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}: ${url}`);
      }
      return resp.result as string;
    } finally {
      client.destroy();
    }
  }

  static async getBuffer(url: string, headers: Record<string, string> | undefined): Promise<ArrayBuffer> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers !== undefined ? headers : Http.defaultHeaders(),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
      };
      const resp: http.HttpResponse = await client.request(url, options);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}: ${url}`);
      }
      return resp.result as ArrayBuffer;
    } finally {
      client.destroy();
    }
  }

  static defaultHeaders(): Record<string, string> {
    return { 'User-Agent': 'MihonHarmony/1.0.0' };
  }
}
