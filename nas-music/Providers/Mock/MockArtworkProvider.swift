//
//  MockArtworkProvider.swift
//  nas-music
//
//  无 NAS 连接时 / SwiftUI Preview 用的封面数据源：用 AppTheme 的渐变色按 coverId 渲染出一张
//  测试图片，不依赖任何本地图片资源或网络请求。
//

import UIKit
import SwiftUI

struct MockArtworkProvider: ArtworkProvider {
    func fetchArtworkData(coverId: String, size: ArtworkSize) async throws -> Data {
        guard !coverId.isEmpty else { throw ArtworkError.missingCoverId }
        let image = Self.renderPlaceholder(seed: coverId, pixelSize: size.maxPixelSize)
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw ArtworkError.invalidImageData
        }
        return data
    }

    private static func renderPlaceholder(seed: String, pixelSize: CGFloat) -> UIImage {
        let side = pixelSize
        let renderer = ImageRenderer(content:
            RoundedRectangle(cornerRadius: 0)
                .fill(AppTheme.artworkGradient(for: seed))
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.32, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(width: side, height: side)
        )
        return renderer.uiImage ?? UIImage()
    }
}
