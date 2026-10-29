// 追踪器注册表（对齐 Mihon TrackerManager；syncId 与 Mihon 一致）
import { Tracker } from './Tracker';
import { MalTracker } from './MalTracker';
import { AniListTracker } from './AniListTracker';
import { KitsuTracker } from './KitsuTracker';
import { ShikimoriTracker } from './ShikimoriTracker';
import { BangumiTracker } from './BangumiTracker';
import { KomgaTracker } from './KomgaTracker';
import { MangaUpdatesTracker } from './MangaUpdatesTracker';
import { HikkaTracker } from './HikkaTracker';
import { KavitaTracker } from './KavitaTracker';
import { SuwayomiTracker } from './SuwayomiTracker';

export class TrackerManager {
  static readonly myAnimeList: MalTracker = new MalTracker();
  static readonly aniList: AniListTracker = new AniListTracker();
  static readonly kitsu: KitsuTracker = new KitsuTracker();
  static readonly shikimori: ShikimoriTracker = new ShikimoriTracker();
  static readonly bangumi: BangumiTracker = new BangumiTracker();
  static readonly komga: KomgaTracker = new KomgaTracker();
  static readonly mangaUpdates: MangaUpdatesTracker = new MangaUpdatesTracker();
  static readonly hikka: HikkaTracker = new HikkaTracker();
  static readonly kavita: KavitaTracker = new KavitaTracker();
  static readonly suwayomi: SuwayomiTracker = new SuwayomiTracker();
  static readonly trackers: Tracker[] = [
    TrackerManager.myAnimeList,
    TrackerManager.aniList,
    TrackerManager.kitsu,
    TrackerManager.shikimori,
    TrackerManager.bangumi,
    TrackerManager.komga,
    TrackerManager.mangaUpdates,
    TrackerManager.hikka,
    TrackerManager.kavita,
    TrackerManager.suwayomi,
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
