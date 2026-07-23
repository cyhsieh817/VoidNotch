//
//  NotchCompactSlotView.swift
//

import SwiftUI
import VoidNotchKit

enum NotchCompactSide {
    case leading
    case trailing
}

struct NotchCompactSlotView: View {
    let side: NotchCompactSide
    let registry: WidgetRegistry
    var onWidth: ((CGFloat) -> Void) = { _ in }

    var body: some View {
        let _ = registry.layout.revision
        let _ = registry.visibilityRevision
        let notchSide: NotchSide = side == .leading ? .leading : .trailing
        let maxW = registry.layout.maxWidth(for: notchSide)
        let height = registry.layout.contentHeight
        Group {
            if registry.layout.isPinned(notchSide) {
                HStack(spacing: side == .leading ? 4 : 6) {
                    ForEach(registry.widgets(on: notchSide).filter(\.hasCompactContent), id: \.id) { widget in
                        widget.compactView()
                            .layoutPriority(Double(widget.priority))
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { onWidth(min(geometry.size.width, maxW)) }
                            .onChange(of: geometry.size.width) { _, newWidth in onWidth(min(newWidth, maxW)) }
                    }
                }
                .frame(maxWidth: maxW, maxHeight: height, alignment: side == .leading ? .leading : .trailing)
                .frame(height: height)
                .frame(maxWidth: maxW, alignment: side == .leading ? .leading : .trailing)
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
                    .clipped()
            }
        }
        .onAppear { syncCollapsedWidth(notchSide) }
        .onChange(of: registry.layout.revision) { syncCollapsedWidth(notchSide) }
    }

    private func syncCollapsedWidth(_ notchSide: NotchSide) {
        if !registry.layout.isPinned(notchSide) { onWidth(0) }
    }
}
