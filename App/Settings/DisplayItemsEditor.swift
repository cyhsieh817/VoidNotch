import SwiftUI
import VoidNotchKit

/// 顯示項目選集編輯器（gauge / menubar 共用）。
///
/// 🔴 身分紀律：整份目錄只能走**一個** ForEach。
/// 舊版把「已選」與「未選」拆成兩個並排 ForEach 畫進同一個 LazyVGrid，兩邊共用
/// `id: \.storageKey`；項目被取消勾選時會從前一個 ForEach 遷移到後一個，SwiftUI
/// 重用了該格位的 checkbox 而不重刷狀態 —— store 明明已寫入，畫面上的勾卻不會消失。
/// 單一 ForEach 讓每個項目在整個格線中身分唯一且恆定，SwiftUI 會「搬移」而非「重用」。
struct DisplayItemsEditor: View {
    let surface: DisplaySurface
    let l10n: L10n
    /// 已選項目（含順序）。真值仍在 store，這裡只是渲染快取。
    @State private var items: [DisplayItem]
    /// 上次讀到的 surface 持久化 raw data；用來過濾無關 defaults 寫入。
    @State private var lastStoredData: Data?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8, alignment: .leading),
        count: 6)

    init(surface: DisplaySurface, l10n: L10n) {
        self.surface = surface
        self.l10n = l10n
        _items = State(initialValue: DisplaySelectionStore.items(for: surface))
        _lastStoredData = State(initialValue: UserDefaults.standard.data(forKey: surface.storageKey))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(orderedCatalog, id: \.storageKey) { item in
                    itemToggle(item)
                }
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator, lineWidth: 0.5)
            }
        }
        .onAppear { reloadFromStore() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let data = UserDefaults.standard.data(forKey: surfaceStorageKey)
            guard data != lastStoredData else { return }
            lastStoredData = data
            reloadFromStore()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(l10n.displayItemsHint)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(l10n.displayItemsCount(items.count, surface.maxItems))
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(isFull ? .orange : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (isFull ? Color.orange : Color.white).opacity(0.12),
                    in: Capsule())

            // 上限不再靜默：滿了就明說為什麼未選的框按不動。
            if isFull {
                Text(l10n.displayItemsFull)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var surfaceStorageKey: String { surface.storageKey }

    private var isFull: Bool { items.count >= surface.maxItems }

    /// 已選（依使用者排序）在前，其餘目錄項目在後——單一序列，身分穩定。
    private var orderedCatalog: [DisplayItem] {
        items + DisplayItem.catalog.filter { !items.contains($0) }
    }

    private func reloadFromStore() {
        let latest = DisplaySelectionStore.items(for: surface)
        if latest != items {
            items = latest
        }
        lastStoredData = UserDefaults.standard.data(forKey: surfaceStorageKey)
    }

    private var language: AppLanguage {
        AppLanguage.resolve(UserDefaults.standard.string(forKey: AppLanguage.preferenceKey))
    }

    @ViewBuilder
    private func itemToggle(_ item: DisplayItem) -> some View {
        let isSelected = items.contains(item)
        let isBlocked = isSelected
            ? !DisplaySelectionStore.canRemove(item, for: surface)
            : !DisplaySelectionStore.canAdd(for: surface)

        // checkbox 與拖曳把手分離：點一下＝toggle，按住圖示／標籤＝排序。
        HStack(spacing: 4) {
            Toggle(
                isOn: Binding(
                    get: { items.contains(item) },
                    set: { newValue in setSelected(newValue, for: item) }))
            {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(isBlocked)

            dragLabel(item, isSelected: isSelected)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .opacity(isBlocked && !isSelected ? 0.45 : 1)
        .help(blockedReason(isSelected: isSelected, isBlocked: isBlocked)
            ?? item.label(language: language))
        .accessibilityLabel(item.label(language: language))
    }

    private func blockedReason(isSelected: Bool, isBlocked: Bool) -> String? {
        guard isBlocked else { return nil }
        return isSelected ? l10n.displayItemsMinimum : l10n.displayItemsFull
    }

    @ViewBuilder
    private func dragLabel(_ item: DisplayItem, isSelected: Bool) -> some View {
        let label = HStack(spacing: 5) {
            Image(systemName: item.iconSystemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14)
            Text(item.label(language: language))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if isSelected {
            label
                .draggable(item.storageKey)
                .dropDestination(for: String.self) { draggedKeys, _ in
                    reorder(draggedKeys: draggedKeys, to: item)
                }
        } else {
            label
        }
    }

    private func setSelected(_ isSelected: Bool, for item: DisplayItem) {
        // 寫入前重讀 store 真值，再套用單一 toggle，避免與右鍵選單互相覆蓋。
        var current = DisplaySelectionStore.items(for: surface)
        if isSelected {
            guard !current.contains(item), DisplaySelectionStore.canAdd(for: surface) else {
                items = current
                return
            }
            current.append(item)
        } else {
            guard DisplaySelectionStore.canRemove(item, for: surface) else {
                items = current
                return
            }
            current.removeAll { $0 == item }
        }
        DisplaySelectionStore.setItems(current, for: surface)
        items = DisplaySelectionStore.items(for: surface)
        lastStoredData = UserDefaults.standard.data(forKey: surfaceStorageKey)
    }

    private func reorder(draggedKeys: [String], to destinationItem: DisplayItem) -> Bool {
        // 以 store 真值為底，再套用拖放後的本地順序意圖。
        var current = DisplaySelectionStore.items(for: surface)
        guard
            let draggedKey = draggedKeys.first,
            let sourceIndex = current.firstIndex(where: { $0.storageKey == draggedKey }),
            let destinationIndex = current.firstIndex(of: destinationItem),
            sourceIndex != destinationIndex
        else {
            items = current
            return false
        }

        let draggedItem = current.remove(at: sourceIndex)
        current.insert(draggedItem, at: destinationIndex)
        DisplaySelectionStore.setItems(current, for: surface)
        items = DisplaySelectionStore.items(for: surface)
        lastStoredData = UserDefaults.standard.data(forKey: surfaceStorageKey)
        return true
    }
}
