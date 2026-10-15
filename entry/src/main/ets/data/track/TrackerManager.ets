// 追踪器注册表（对齐 Mihon TrackerManager；syncId 与 Mihon 一致）
import { Tracker } from './Tracker';
import { MalTracker } from './MalTracker';
import { AniListTracker } from './AniListTracker';
import { KitsuTracker } from './KitsuTracker';
import { ShikimoriTracker } from './ShikimoriTracker';
import { BangumiTracker } from './BangumiTracker';
import { MangaUpdatesTracker } from './MangaUpdatesTracker';
import { HikkaTracker } from './HikkaTracker';
import { MangaBakaTracker } from './MangaBakaTracker';

export class TrackerManager {
  static readonly myAnimeList: MalTracker = new MalTracker();
  static readonly aniList: AniListTracker = new AniListTracker();
  static readonly kitsu: KitsuTracker = new KitsuTracker();
  static readonly shikimori: ShikimoriTracker = new ShikimoriTracker();
  static readonly bangumi: BangumiTracker = new BangumiTracker();
  static readonly mangaUpdates: MangaUpdatesTracker = new MangaUpdatesTracker();
  static readonly hikka: HikkaTracker = new HikkaTracker();
  static readonly mangaBaka: MangaBakaTracker = new MangaBakaTracker();

  static readonly trackers: Tracker[] = [
    TrackerManager.myAnimeList,
    TrackerManager.aniList,
    TrackerManager.kitsu,
    TrackerManager.shikimori,
    TrackerManager.bangumi,
    TrackerManager.mangaUpdates,
    TrackerManager.hikka,
    TrackerManager.mangaBaka,
  ];

  static loggedInTrackers(): Tracker[] {
    const list: Tracker[] = [];
    for (const t of TrackerManager.trackers) {
      if (t.isLoggedIn()) {
        list.push(t);
      }
    }
    return list;
  }

  static get(id: number): Tracker | undefined {
    for (const t of TrackerManager.trackers) {
      if (t.syncId === id) {
        return t;
      }
    }
    return undefined;
  }

  static getAll(ids: number[]): Tracker[] {
    const list: Tracker[] = [];
    for (const t of TrackerManager.trackers) {
      if (ids.includes(t.syncId)) {
        list.push(t);
      }
    }
    return list;
  }
}
