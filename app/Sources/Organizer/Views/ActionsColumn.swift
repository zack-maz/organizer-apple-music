//
// ActionsColumn.swift
//
// One row per script, grouped: name, options, one button. Destructive actions
// offer "Preview", which runs the dry run; the confirm bar in the console then
// offers the real run. What each script does is explained on the Docs tab.
//

import SwiftUI
import OrganizerCore

struct ActionsColumn: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ActionGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.rawValue).label()
                        if let reason = group.disabledReason {
                            Text(reason).small(Palette.muted)
                        }
                    }
                    .id(group == .build ? "top" : group.id)
                    .padding(.horizontal, 28)
                    .padding(.top, group == .build ? 22 : 30)
                    .padding(.bottom, 10)
                    // a disabled group stays visible but greyed and inert
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.kinds) { kind in
                            ActionRow(kind: kind)
                        }
                    }
                    .disabled(group.disabledReason != nil)
                    .opacity(group.disabledReason != nil ? 0.35 : 1)
                }
                ScriptsFooter()
                    .padding(.top, 36)
            }
            .padding(.bottom, 28)
        }
        // Start at the top: a text field taking first responder on launch
        // would otherwise scroll the column to itself.
        .defaultScrollAnchor(.top)
        .onAppear { DispatchQueue.main.async { proxy.scrollTo("top", anchor: .top) } }
        }
    }
}

private struct ActionRow: View {
    @EnvironmentObject private var model: AppModel
    let kind: ActionKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.rawValue).small(Palette.bright, weight: .medium)
                if kind.isDestructive {
                    Text("preview · confirm").label()
                }
                Spacer()
                Button(kind.isDestructive ? "Preview" : "Run") {
                    kind.isDestructive ? model.preview(kind) : model.run(kind)
                }
                .buttonStyle(HairlineButtonStyle())
                .disabled(!canRun)
            }
            options
                .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Hairline() }
    }

    private var canRun: Bool {
        if model.isRunning || kind.group.disabledReason != nil { return false }
        if kind == .restorePlaylists { return !model.options.restoreDirectory.isEmpty }
        return true
    }

    @ViewBuilder private var options: some View {
        switch kind {
        case .buildGenres:
            // unchecked: incremental, only unfiled tracks are touched;
            // checked: --replace, delete the folder and rebuild everything
            VStack(alignment: .leading, spacing: 12) {
                Toggle(model.options.replace ? "delete and rebuild" : "add only what's new", isOn: $model.options.replace)
                    .toggleStyle(SquareToggleStyle())
                    .help("Unchecked: append new tracks to existing playlists, create playlists for new genres. Checked (--replace): delete the folder and rebuild from scratch.")
                HStack(spacing: 20) {
                    OptionField(label: "folder", text: $model.options.folder)
                    OptionNumberField(label: "min-tracks", value: $model.options.minTracks)
                }
            }
        case .whatsNew:
            HStack(spacing: 20) {
                OptionNumberField(label: "days", value: $model.options.days)
                Toggle("all", isOn: $model.options.showAll).toggleStyle(SquareToggleStyle())
                OptionField(label: "folder", text: $model.options.folder)
            }
        case .dedupePlaylists, .downloadReport, .downloadGenres:
            OptionField(label: "folder", text: $model.options.folder)
        case .watchDownloads:
            HStack(spacing: 20) {
                OptionNumberField(label: "interval", value: $model.options.watchInterval, width: 48)
                    .help("Seconds between checks. Read-only: it never queues anything.")
                OptionField(label: "folder", text: $model.options.folder)
            }
        case .markUnavailable:
            OptionField(label: "name", text: $model.options.unavailableName, width: 140)
        case .backupPlaylists:
            HStack(spacing: 12) {
                Text("to").label()
                Text(abbreviated(model.options.backupsRoot))
                    .font(Typeface.mono(12))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Change") { model.chooseBackupsFolder() }.buttonStyle(HairlineButtonStyle())
            }
        case .restorePlaylists:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("from").label()
                    Text(model.options.restoreDirectory.isEmpty ? "no backup chosen" : abbreviated(model.options.restoreDirectory))
                        .font(Typeface.mono(12))
                        .foregroundStyle(model.options.restoreDirectory.isEmpty ? Palette.muted : Palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose") { model.chooseRestoreFolder() }.buttonStyle(HairlineButtonStyle())
                }
                OptionField(label: "names", text: $model.options.restoreNames, width: 220)
                    .help("Optional, comma-separated. Empty restores everything except Apple's built-ins.")
            }
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Where the scripts are read from, with an override for editing in the repo.
private struct ScriptsFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 12) {
                Text("scripts").label()
                Text(model.locator.description)
                    .font(Typeface.mono(12))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change") { model.chooseScriptsFolder() }.buttonStyle(HairlineButtonStyle())
                if case .override = model.locator.source {
                    Button("Bundled") { model.useBundledScripts() }.buttonStyle(HairlineButtonStyle())
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .disabled(model.isRunning)
        }
    }
}
