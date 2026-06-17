//
//  AlbumArtView.swift
//  nas-music
//
//  Mock 占位封面：没有真实图片资源时，用渐变色 + 音符图标模拟专辑/歌曲封面。
//

import SwiftUI

struct AlbumArtView: View {
    let id: String
    var cornerRadius: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.artworkGradient(for: id))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: proxy.size.width * 0.32, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    AlbumArtView(id: "preview")
        .frame(width: 140, height: 140)
}
