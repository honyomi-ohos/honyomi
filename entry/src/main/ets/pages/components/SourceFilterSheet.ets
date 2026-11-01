import { RawFilter } from '../../source/JsvmSource';
import { ThemePalette } from '../../common/Theme';
import { AppIcon } from './AppIcon';

// sort 过滤器选中态（对齐 Mihon Filter.Sort.Selection：{index, ascending}）
export class FilterSortSelection {
  index: number = 0;
  ascending: boolean = true;
}

// 插件自定义过滤器半模态面板（对齐 Mihon SourceFilterDialog）：
// select/checkbox/tristate/text/sort/group 全类型渲染，底部固定 重置|过滤 操作区。
// 单源浏览页与迁移搜索页共用；过滤器状态经 @Link 与父页面共享，
// 嵌套 state 变更由 filterRev 计数驱动 ForEach 重建，父页面替换 filters 数组经 @Watch 自动刷新。
@Component
export struct SourceFilterSheet {
  @StorageProp('palette') pal: ThemePalette = new ThemePalette();
  @Link @Watch('onFiltersReplaced') filters: RawFilter[];
  // 面板刷新计数：嵌套 state 变更后递增触发 ForEach 重建
  @State filterRev: number = 0;
  // 应用/重置回调（父页面负责 applyFilterState/resetFilters 与搜索触发）
  onApply: () => void = (): void => {
  };
  onReset: () => void = (): void => {
  };

  // 父页面替换 filters（打开面板拉取/重置后回填）时刷新面板
  onFiltersReplaced(): void {
    this.filterRev++;
  }

  build() {
    Column() {
      if (this.filters.length === 0) {
        Text($r('app.string.browse_filter_empty'))
          .fontSize(14)
          .fontColor(this.pal.sub)
          .padding({ top: 32, bottom: 32 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.filters, (filter: RawFilter, index: number) => {
              if (filter.type === 'group') {
                this.filterGroupBuilder(filter, `f${index}`)
              } else {
                this.filterLeafBuilder(filter)
              }
            }, (filter: RawFilter, index: number): string => `flt-${index}-${this.filterRev}`)
          }
          .width('100%')
          .padding({
            left: 24,
            right: 24,
            top: 4,
            bottom: 8
          })
        }
        .width('100%')
        .scrollBar(BarState.Off)
      }

      Divider()
        .color(this.pal.divider)
        .margin({ left: 24, right: 24 })

      // 底部操作区：重置（次要）+ 过滤（主操作）等宽双按钮
      Row({ space: 12 }) {
        Button($r('app.string.browse_filter_reset'))
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .backgroundColor(this.pal.chip)
          .fontColor(this.pal.text)
          .onClick(() => {
            this.onReset();
          })
        Button($r('app.string.action_filter'))
          .layoutWeight(1)
          .height(40)
          .fontSize(16)
          .backgroundColor(this.pal.primary)
          .fontColor(this.pal.onPrimary)
          .onClick(() => {
            this.onApply();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 24 })
    }
    .width('100%')
  }

  // select 过滤器：标签 + 下拉框（点击展开选项列表）
  @Builder
  filterSelectBuilder(filter: RawFilter) {
    Column() {
      Text(filter.name ?? '')
        .fontSize(14)
        .fontColor(this.pal.sub)
        .margin({ top: 12, bottom: 8 })
      Select(this.selectOptions(filter))
        .selected(this.selectIndex(filter))
        .value(this.selectValueText(filter))
        .width('100%')
        .height(40)
        .font({ size: 16 })
        .fontColor(this.pal.text)
        .backgroundColor(this.pal.chip)
        .borderRadius(8)
        .onSelect((index: number, _text?: string) => {
          this.setFilterSelect(filter, index);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // checkbox 过滤器：图标 + 名称整行，点击勾选/取消（对齐 Mihon CheckboxItem）
  @Builder
  filterCheckboxBuilder(filter: RawFilter) {
    Row() {
      AppIcon({
        name: filter.state === true ? 'check_box' : 'check_box_outline_blank',
        iconSize: 24,
        tint: filter.state === true ? this.pal.primary : this.pal.sub,
      })
        .margin({ right: 16 })
      Text(filter.name ?? '')
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleFilterCheckbox(filter);
    })
  }

  // tri-state 过滤器：图标 + 名称整行，点击循环 忽略→包含→排除（对齐 Mihon TriStateItem）
  @Builder
  filterTristateBuilder(filter: RawFilter) {
    Row() {
      AppIcon({
        name: this.filterTriIcon(this.filterNumberState(filter, 0)),
        iconSize: 24,
        tint: this.filterNumberState(filter, 0) === 0 ? this.pal.sub : this.pal.primary,
      })
        .margin({ right: 16 })
      Text(filter.name ?? '')
        .fontSize(16)
        .fontColor(this.pal.text)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.cycleFilterTristate(filter);
    })
  }

  // text 过滤器：标签 + 输入框
  @Builder
  filterTextBuilder(filter: RawFilter) {
    Column() {
      Text(filter.name ?? '')
        .fontSize(14)
        .fontColor(this.pal.sub)
        .margin({ top: 12, bottom: 8 })
      TextInput({ text: typeof filter.state === 'string' ? filter.state as string : '' })
        .height(40)
        .fontSize(16)
        .backgroundColor(this.pal.chip)
        .onChange((value: string) => {
          filter.state = value;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // sort 过滤器：标签 + 排序选项单选列表（对齐 Mihon SortItem）：
  // 点击未选项 → 选中并默认升序；再点已选项 → 切换升/降序，行尾箭头指示方向
  @Builder
  filterSortBuilder(filter: RawFilter) {
    Column() {
      Text(filter.name ?? '')
        .fontSize(14)
        .fontColor(this.pal.sub)
        .margin({ top: 12, bottom: 4 })
      ForEach(this.sortValues(filter), (value: string, index: number) => {
        Row() {
          Radio({ value: `${index}`, group: filter.name ?? 'sort' })
            .checked(this.sortIndex(filter) === index)
            .width(20)
            .height(20)
            .margin({ right: 16 })
            .hitTestBehavior(HitTestMode.None)
          Text(value)
            .fontSize(16)
            .fontColor(this.pal.text)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.sortIndex(filter) === index) {
            AppIcon({
              name: this.sortAscending(filter) ? 'arrow_upward' : 'arrow_downward',
              iconSize: 20,
              tint: this.pal.primary,
            })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.pickSortValue(filter, index);
        })
      }, (value: string, index: number): string => `sort-${index}-${this.filterRev}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 单个过滤器分发（未知类型不渲染）
  @Builder
  filterLeafBuilder(filter: RawFilter) {
    Column() {
      if (filter.type === 'select') {
        this.filterSelectBuilder(filter)
      } else if (filter.type === 'checkbox') {
        this.filterCheckboxBuilder(filter)
      } else if (filter.type === 'tristate' || filter.type === 'tri-state') {
        this.filterTristateBuilder(filter)
      } else if (filter.type === 'text') {
        this.filterTextBuilder(filter)
      } else if (filter.type === 'sort') {
        this.filterSortBuilder(filter)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // group 过滤器：组名标题 + 子项逐行展示（对齐 Mihon Filter.Group）
  @Builder
  filterGroupBuilder(group: RawFilter, idPrefix: string) {
    Column() {
      if ((group.name ?? '') !== '') {
        Text(group.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.sub)
          .margin({ top: 16, bottom: 8 })
      }
      ForEach(group.filters ?? [], (sub: RawFilter, subIndex: number) => {
        this.filterLeafBuilder(sub)
      }, (sub: RawFilter, subIndex: number): string => `${idPrefix}-g${subIndex}-${this.filterRev}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private setFilterSelect(filter: RawFilter, index: number): void {
    filter.state = index;
    this.filterRev++;
  }

  private toggleFilterCheckbox(filter: RawFilter): void {
    filter.state = filter.state !== true;
    this.filterRev++;
  }

  // tri-state 点击循环：0 忽略 → 1 包含 → 2 排除 → 0（对齐 Mihon TriStateItem）
  private cycleFilterTristate(filter: RawFilter): void {
    const cur = this.filterNumberState(filter, 0);
    filter.state = cur === 0 ? 1 : (cur === 1 ? 2 : 0);
    this.filterRev++;
  }

  // tri-state 图标：0 空心 / 1 勾选 / 2 禁用（对齐 Mihon TriState 图标）
  private filterTriIcon(state: number): string {
    if (state === 1) {
      return 'check_box';
    }
    if (state === 2) {
      return 'disabled_by_default';
    }
    return 'check_box_outline_blank';
  }

  private filterNumberState(filter: RawFilter, fallback: number): number {
    return typeof filter.state === 'number' ? filter.state as number : fallback;
  }

  // select 过滤器选中下标（越界钳制到有效范围）
  private selectIndex(filter: RawFilter): number {
    const len = (filter.values ?? []).length;
    if (len === 0) {
      return 0;
    }
    const idx = this.filterNumberState(filter, 0);
    return Math.min(Math.max(idx, 0), len - 1);
  }

  // select 过滤器下拉选项（对齐 Mihon SelectItem 的 ExposedDropdownMenu）
  private selectOptions(filter: RawFilter): SelectOption[] {
    const options: SelectOption[] = [];
    const values = filter.values ?? [];
    for (let i = 0; i < values.length; i++) {
      const opt: SelectOption = { value: String(values[i]) };
      options.push(opt);
    }
    return options;
  }

  // select 过滤器当前选中值文本
  private selectValueText(filter: RawFilter): string {
    const values = filter.values ?? [];
    const idx = this.selectIndex(filter);
    if (idx < values.length) {
      return String(values[idx]);
    }
    return '';
  }

  // sort 过滤器选项名列表
  private sortValues(filter: RawFilter): string[] {
    const values: string[] = [];
    const raw = filter.values ?? [];
    for (let i = 0; i < raw.length; i++) {
      values.push(String(raw[i]));
    }
    return values;
  }

  // sort 过滤器当前选中下标（未选/非法返回 -1）
  private sortIndex(filter: RawFilter): number {
    const state = filter.state;
    if (typeof state !== 'object' || state === null || Array.isArray(state)) {
      return -1;
    }
    const sel: Record<string, Object> = state as Record<string, Object>;
    const idx: Object | undefined = sel['index'];
    return typeof idx === 'number' ? idx as number : -1;
  }

  // sort 过滤器当前方向（未选/非法默认升序）
  private sortAscending(filter: RawFilter): boolean {
    const state = filter.state;
    if (typeof state !== 'object' || state === null || Array.isArray(state)) {
      return true;
    }
    const sel: Record<string, Object> = state as Record<string, Object>;
    const asc: Object | undefined = sel['ascending'];
    return asc === true;
  }

  // 点击排序选项：未选中 → 选中并升序；已选中 → 切换升/降序（对齐 Mihon SortItem）
  private pickSortValue(filter: RawFilter, index: number): void {
    const next = new FilterSortSelection();
    next.index = index;
    next.ascending = this.sortIndex(filter) === index ? !this.sortAscending(filter) : true;
    filter.state = next;
    this.filterRev++;
  }
}
