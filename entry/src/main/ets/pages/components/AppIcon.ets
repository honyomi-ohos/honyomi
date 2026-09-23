// 应用内图标组件：单套 material-symbols SVG（无 fill 属性），
// 使用时通过 fillColor 以当前主题色板填充（默认 pal.text，可用 tint 覆盖）。
// 用法：AppIcon({ name: 'search', iconSize: 24 })，name 为 icons 名（不带 ic_ 前缀）。
import { ThemePalette } from '../../common/Theme';

const ICONS: Record<string, Resource> = {
  'collections_bookmark': $r('app.media.ic_collections_bookmark'),
  'new_releases': $r('app.media.ic_new_releases'),
  'schedule': $r('app.media.ic_schedule'),
  'explore': $r('app.media.ic_explore'),
  'more_vert': $r('app.media.ic_more_vert'),
  'search': $r('app.media.ic_search'),
  'filter_list': $r('app.media.ic_filter_list'),
  'refresh': $r('app.media.ic_refresh'),
  'download': $r('app.media.ic_download'),
  'settings': $r('app.media.ic_settings'),
  'close': $r('app.media.ic_close'),
  'add': $r('app.media.ic_add'),
  'delete': $r('app.media.ic_delete'),
  'delete_sweep': $r('app.media.ic_delete_sweep'),
  'share': $r('app.media.ic_share'),
  'select_all': $r('app.media.ic_select_all'),
  'deselect': $r('app.media.ic_deselect'),
  'done_all': $r('app.media.ic_done_all'),
  'done': $r('app.media.ic_done'),
  'bookmark': $r('app.media.ic_bookmark'),
  'cancel': $r('app.media.ic_cancel'),
  'error': $r('app.media.ic_error'),
  'warning': $r('app.media.ic_warning'),
  'info': $r('app.media.ic_info'),
  'view_module': $r('app.media.ic_view_module'),
  'keyboard_arrow_right': $r('app.media.ic_keyboard_arrow_right'),
  'keyboard_arrow_left': $r('app.media.ic_keyboard_arrow_left'),
  'expand_more': $r('app.media.ic_expand_more'),
  'expand_less': $r('app.media.ic_expand_less'),
  'push_pin': $r('app.media.ic_push_pin'),
  'public': $r('app.media.ic_public'),
  'query_stats': $r('app.media.ic_query_stats'),
  'storage': $r('app.media.ic_storage'),
  'arrow_upward': $r('app.media.ic_arrow_upward'),
  'arrow_downward': $r('app.media.ic_arrow_downward'),
  'visibility': $r('app.media.ic_visibility'),
  'visibility_off': $r('app.media.ic_visibility_off'),
  'cloud_off': $r('app.media.ic_cloud_off'),
  'file_download_off': $r('app.media.ic_file_download_off'),
  'sync': $r('app.media.ic_sync'),
  'autorenew': $r('app.media.ic_autorenew'),
  'image': $r('app.media.ic_image'),
  'content_copy': $r('app.media.ic_content_copy'),
  'drag_handle': $r('app.media.ic_drag_handle'),
  'travel_explore': $r('app.media.ic_travel_explore'),
  'palette': $r('app.media.ic_palette'),
  'screen_rotation': $r('app.media.ic_screen_rotation'),
  'hourglass_empty': $r('app.media.ic_hourglass_empty'),
  'photo': $r('app.media.ic_photo'),
  'edit': $r('app.media.ic_edit'),
  'folder': $r('app.media.ic_folder'),
  'arrow_back': $r('app.media.ic_arrow_back'),
  'arrow_forward': $r('app.media.ic_arrow_forward'),
  'sort': $r('app.media.ic_sort'),
  'view_list': $r('app.media.ic_view_list'),
  'open_in_new': $r('app.media.ic_open_in_new'),
  'label': $r('app.media.ic_label'),
  'bookmark_filled': $r('app.media.ic_bookmark_filled'),
  'check_circle': $r('app.media.ic_check_circle'),
  'pause': $r('app.media.ic_pause'),
  'play_arrow': $r('app.media.ic_play_arrow'),
  'push_pin_filled': $r('app.media.ic_push_pin_filled'),
  'favorite': $r('app.media.ic_favorite'),
  'skip_previous': $r('app.media.ic_skip_previous'),
  'skip_next': $r('app.media.ic_skip_next'),
  'crop': $r('app.media.ic_crop'),
  'crop_off': $r('app.media.ic_crop_off'),
  'reader_ltr': $r('app.media.ic_reader_ltr'),
  'reader_rtl': $r('app.media.ic_reader_rtl'),
  'reader_webtoon': $r('app.media.ic_reader_webtoon'),
  'tab_library': $r('app.media.ic_tab_library'),
  'tab_library_on': $r('app.media.ic_tab_library_on'),
  'tab_updates': $r('app.media.ic_tab_updates'),
  'tab_updates_on': $r('app.media.ic_tab_updates_on'),
  'tab_history_hands': $r('app.media.ic_tab_history_hands'),
  'tab_history_arrow': $r('app.media.ic_tab_history_arrow'),
  'tab_browse': $r('app.media.ic_tab_browse'),
  'tab_browse_on': $r('app.media.ic_tab_browse_on'),
  'tab_browse_dot': $r('app.media.ic_tab_browse_dot'),
  'tab_browse_ring': $r('app.media.ic_tab_browse_ring')
};

export class AppIconRes {
  static get(name: string): Resource {
    const res: Resource | undefined = ICONS[name];
    if (res !== undefined) {
      return res;
    }
    const fallback: Resource | undefined = ICONS['more_vert'];
    if (fallback !== undefined) {
      return fallback;
    }
    return $r('app.media.startIcon');
  }
}

@Component
export struct AppIcon {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Prop name: string = '';
  @Prop iconSize: number = 24;
  @Prop tint: ResourceColor = '';

  build() {
    Image(AppIconRes.get(this.name))
      .width(this.iconSize)
      .height(this.iconSize)
      .fillColor(this.tint !== '' ? this.tint : this.pal.text)
  }
}
