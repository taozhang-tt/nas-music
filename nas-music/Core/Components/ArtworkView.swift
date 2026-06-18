//
//  ArtworkView.swift
//  nas-music
//
//  统一的封面组件：列表小图/专辑中图/播放器大图都用这一个 View，内部调用
//  ArtworkImageLoader（经 ArtworkImageViewModel）异步加载，加载中/失败都不需要调用方
//  关心——失败或没有 coverId 时静默回退到 AlbumArtView 的渐变占位封面。
//

import SwiftUI

struct ArtworkView: View {
    let coverId: String?
    var size: ArtworkSize = .thumbnail
    var cornerRadius: CGFloat = 8
    /// 没有真实封面时占位渐变的取色种子，传歌曲/专辑自身的 id 让占位图在列表里保持稳定、
    /// 各不相同；不传则用 coverId 兜底。
    var placeholderSeed: String?

    @StateObject private var viewModel = ArtworkImageViewModel()

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .aspectRatio(1, contentMode: .fit)
            .task(id: requestID) {
                viewModel.load(coverId: coverId, size: size)
            }
    }

    private var requestID: String {
        "\(coverId ?? "")|\(size.rawValue)"
    }

    @ViewBuilder
    private var content: some View {
        if let image = viewModel.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if viewModel.isLoading {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .overlay {
                    ProgressView()
                        .scaleEffect(0.7)
                }
        } else {
            AlbumArtView(id: placeholderSeed ?? coverId ?? "placeholder", cornerRadius: cornerRadius)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ArtworkView(coverId: "album-novembers-chopin", size: .thumbnail, cornerRadius: 6)
            .frame(width: 44, height: 44)
        ArtworkView(coverId: "album-1989-tv", size: .medium, cornerRadius: 8)
            .frame(width: 140, height: 140)
        ArtworkView(coverId: nil, size: .large, cornerRadius: 16, placeholderSeed: "fallback")
            .frame(width: 240, height: 240)
    }
    .padding()
}
