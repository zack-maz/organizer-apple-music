//
// DocsColumn.swift
//
// One entry per command: what it does, when to use it, and its flags. Rules
// between entries and between flag rows; no cards.
//

import SwiftUI
import OrganizerCore

struct DocsColumn: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("docs").label().id("top")
                    Text(Docs.preamble)
                        .font(Typeface.text(14))
                        .foregroundStyle(Palette.text)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Docs.dryRunNote)
                        .caption()
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 26)

                ForEach(Docs.all) { doc in
                    DocEntry(doc: doc).id(doc.id)
                }
            }
            .padding(.bottom, 28)
        }
        .defaultScrollAnchor(.top)
        // The column can appear after the window has already laid out (tab
        // switch, launch argument); pin it to the top once it does.
        .onAppear {
            let target = model.docsTarget?.id ?? "top"
            DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
        }
        }
    }
}

private struct DocEntry: View {
    let doc: CommandDoc

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(doc.kind.rawValue).small(Palette.bright, weight: .medium)
                Spacer()
                Text(doc.kind.group.rawValue).label()
            }
            Text(doc.does)
                .font(Typeface.text(14))
                .foregroundStyle(Palette.text)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("when").label()
                Text(doc.when)
                    .caption(Palette.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("flags").label()
                    .padding(.bottom, 8)
                ForEach(doc.flags) { flag in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(flag.flag)
                            .font(Typeface.mono(12))
                            .foregroundStyle(Palette.bright)
                            .frame(width: 128, alignment: .leading)
                        Text(flag.meaning)
                            .caption(Palette.text)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Hairline() }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .overlay(alignment: .top) { Hairline() }
    }
}
