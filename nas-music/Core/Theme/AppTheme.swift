//
//  AppTheme.swift
//  nas-music
//

import SwiftUI

enum AppTheme {
    static let playerBackgroundTop = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let playerBackgroundBottom = Color.black

    private static let artworkGradients: [[Color]] = [
        [Color(hex: 0xFF6B6B), Color(hex: 0xFFD93D)],
        [Color(hex: 0x4ECDC4), Color(hex: 0x556270)],
        [Color(hex: 0x6C5CE7), Color(hex: 0xA29BFE)],
        [Color(hex: 0xF7971E), Color(hex: 0xFFD200)],
        [Color(hex: 0x00B09B), Color(hex: 0x96C93D)],
        [Color(hex: 0xEE0979), Color(hex: 0xFF6A00)],
        [Color(hex: 0x2193B0), Color(hex: 0x6DD5ED)],
        [Color(hex: 0x373B44), Color(hex: 0x4286F4)],
    ]

    static func artworkGradient(for id: String) -> LinearGradient {
        let index = abs(id.hashValue) % artworkGradients.count
        return LinearGradient(
            colors: artworkGradients[index],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
