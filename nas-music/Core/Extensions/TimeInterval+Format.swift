//
//  TimeInterval+Format.swift
//  nas-music
//

import Foundation

extension TimeInterval {
    var formattedAsMinutesSeconds: String {
        guard isFinite, self >= 0 else { return "00:00" }
        let totalSeconds = Int(self.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var formattedAsHoursMinutes: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(minutes) 分钟"
    }
}
