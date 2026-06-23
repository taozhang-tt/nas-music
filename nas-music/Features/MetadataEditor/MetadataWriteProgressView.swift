//
//  MetadataWriteProgressView.swift
//  nas-music
//

import SwiftUI

struct MetadataWriteProgressView: View {
    let isWriting: Bool
    let message: String?

    var body: some View {
        if isWriting {
            HStack {
                ProgressView()
                Text("正在写入 NAS 文件…")
            }
        } else if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

