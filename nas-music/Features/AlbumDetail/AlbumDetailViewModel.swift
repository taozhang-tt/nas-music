//
//  AlbumDetailViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    let album: Album

    init(album: Album) {
        self.album = album
    }

    var formattedDuration: String { album.totalDuration.formattedAsMinutesSeconds }
}
