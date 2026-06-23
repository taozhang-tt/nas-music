//
//  BatchMetadataEditorView.swift
//  nas-music
//

import SwiftUI

struct BatchMetadataEditorView: View {
    var body: some View {
        ContentUnavailableView(
            "批量标签转换尚未启用",
            systemImage: "square.stack.3d.up",
            description: Text("批量写回需要逐首预览、限流和失败隔离，当前版本先开放单曲写回。")
        )
        .navigationTitle("批量标签转换")
    }
}

