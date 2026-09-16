//
// RootView.swift
//
// Header, the overview strip, then Actions on the left and the Console on the
// right. Sections are separated by hairlines, not boxes.
//

import SwiftUI
import OrganizerCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 22)
            Hairline()
            OverviewStrip()
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            Hairline()
            HStack(spacing: 0) {
                Group {
                    switch model.tab {
                    case .actions: ActionsColumn()
                    case .docs: DocsColumn()
                    }
                }
                .frame(width: 480)
                Hairline(axis: .vertical)
                ConsoleView()
            }
        }
        .background(Palette.void)
        .background(WindowConfigurator())
        .frame(minWidth: 1040, minHeight: 680)
        .preferredColorScheme(.dark)
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("organizer").small(Palette.bright, weight: .medium)
            Text("apple music").font(Typeface.mono(12)).foregroundStyle(Palette.muted)
            HStack(spacing: 22) {
                ForEach(Tab.allCases) { tab in
                    LabelTab(title: tab.rawValue, selected: model.tab == tab) { model.tab = tab }
                }
            }
            .padding(.leading, 40)
            Spacer()
            if let at = model.lastRefreshed {
                Text("refreshed \(at.formatted(date: .omitted, time: .shortened))")
                    .font(Typeface.mono(12))
                    .foregroundStyle(Palette.muted)
            }
            Button("Refresh") { model.refresh() }
                .buttonStyle(HairlineButtonStyle())
                .disabled(model.isRunning)
                .help("Reads the library: whats-new, then dedupe-playlists --dry-run. Changes nothing.")
        }
    }
}

/// The numbers STATE.md tracks by hand, at the Title scale.
private struct OverviewStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Stat(value: model.overview.tracks, label: "tracks", detail: "in library")
            Hairline(axis: .vertical)
            Stat(value: model.overview.filed, label: "filed", detail: "in \(model.options.folder)")
            Hairline(axis: .vertical)
            Stat(value: model.overview.unfiled, label: "unfiled", detail: "since last rebuild")
            Hairline(axis: .vertical)
            Stat(value: model.overview.duplicateRows, label: "duplicate rows", detail: "rows minus distinct")
            Hairline(axis: .vertical)
            Stat(value: model.overview.playlists, label: "playlists", detail: "genre playlists")
            Hairline(axis: .vertical)
            Stat(value: model.overview.folders, label: "folders", detail: "parent folders")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Stat: View {
    let value: Int?
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value.map { $0.formatted(.number.grouping(.automatic)) } ?? "—")
                .title(value == nil ? Palette.muted : Palette.bright)
                .monospacedDigit()
            Text(label).label(Palette.bright)
            Text(detail).caption()
        }
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
