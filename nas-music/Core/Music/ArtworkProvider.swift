//
//  ArtworkProvider.swift
//  nas-music
//
//  封面数据源抽象：MockArtworkProvider 用于无 NAS 连接时开发/预览，
//  SynologyArtworkProvider 接入真实 Audio Station 封面接口。ArtworkImageLoader 只依赖
//  这个协议，不关心封面具体来自哪个数据源。
//

import UIKit

enum ArtworkSize: String, Codable, CaseIterable {
    case thumbnail
    case medium
    case large
}

extension ArtworkSize {
    /// 下载/解码时的目标最大像素边长，避免把整张原图解码进内存。
    var maxPixelSize: CGFloat {
        switch self {
        case .thumbnail: return 200
        case .medium: return 600
        case .large: return 1200
        }
    }
}

protocol ArtworkProvider {
    func fetchArtworkData(coverId: String, size: ArtworkSize) async throws -> Data
    func fetchArtworkImage(coverId: String, size: ArtworkSize) async throws -> UIImage
}

extension ArtworkProvider {
    /// 大多数实现只需要提供 fetchArtworkData；这里统一负责把 Data 解码成 UIImage。
    func fetchArtworkImage(coverId: String, size: ArtworkSize) async throws -> UIImage {
        let data = try await fetchArtworkData(coverId: coverId, size: size)
        guard let image = UIImage(data: data) else { throw ArtworkError.invalidImageData }
        return image
    }
}
