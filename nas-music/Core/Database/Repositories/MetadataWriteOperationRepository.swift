//
//  MetadataWriteOperationRepository.swift
//  nas-music
//

import Foundation

protocol MetadataWriteOperationRepositoryProtocol {
    func upsert(_ record: MetadataWriteOperationRecord) async throws
    func latest(nasId: String, sourceId: String) async throws -> MetadataWriteOperationRecord?
}

final class MetadataWriteOperationRepository: MetadataWriteOperationRepositoryProtocol {
    private let database: DatabaseManager

    init(database: DatabaseManager = .shared) {
        self.database = database
    }

    func upsert(_ record: MetadataWriteOperationRecord) async throws {
        try await Task.detached {
            try self.database.write { db in
                let statement = try SQLStatement("""
                    INSERT INTO metadata_write_operations (
                        id,nas_id,song_id,source_id,status,old_revision,new_revision,
                        before_metadata_json,after_metadata_json,backup_available,error_message,created_at,completed_at
                    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET
                        status=excluded.status,
                        new_revision=excluded.new_revision,
                        after_metadata_json=excluded.after_metadata_json,
                        backup_available=excluded.backup_available,
                        error_message=excluded.error_message,
                        completed_at=excluded.completed_at
                    """, db: db)
                try Self.bind(record, to: statement)
                _ = try statement.step()
            }
        }.value
    }

    func latest(nasId: String, sourceId: String) async throws -> MetadataWriteOperationRecord? {
        try await Task.detached {
            try self.database.read { db in
                let statement = try SQLStatement("""
                    SELECT id,nas_id,song_id,source_id,status,old_revision,new_revision,
                           before_metadata_json,after_metadata_json,backup_available,error_message,created_at,completed_at
                    FROM metadata_write_operations
                    WHERE nas_id = ? AND source_id = ?
                    ORDER BY created_at DESC
                    LIMIT 1
                    """, db: db)
                try statement.bind(nasId, at: 1)
                try statement.bind(sourceId, at: 2)
                guard try statement.step() else { return nil }
                return Self.readRecord(from: statement)
            }
        }.value
    }

    private static func bind(_ record: MetadataWriteOperationRecord, to statement: SQLStatement) throws {
        try statement.bind(record.id, at: 1)
        try statement.bind(record.nasId, at: 2)
        try statement.bind(record.songId, at: 3)
        try statement.bind(record.sourceId, at: 4)
        try statement.bind(record.status.rawValue, at: 5)
        try statement.bind(record.oldRevision, at: 6)
        try statement.bind(record.newRevision, at: 7)
        try statement.bind(record.beforeMetadataJSON, at: 8)
        try statement.bind(record.afterMetadataJSON, at: 9)
        try statement.bind(record.backupAvailable ? 1 : 0, at: 10)
        try statement.bind(record.errorMessage, at: 11)
        try statement.bind(record.createdAt.timeIntervalSince1970, at: 12)
        try statement.bind(record.completedAt?.timeIntervalSince1970, at: 13)
    }

    private static func readRecord(from statement: SQLStatement) -> MetadataWriteOperationRecord {
        MetadataWriteOperationRecord(
            id: statement.string(0) ?? "",
            nasId: statement.string(1) ?? "",
            songId: statement.string(2) ?? "",
            sourceId: statement.string(3) ?? "",
            status: MetadataWriteStatus(rawValue: statement.string(4) ?? "") ?? .idle,
            oldRevision: statement.string(5),
            newRevision: statement.string(6),
            beforeMetadataJSON: statement.string(7),
            afterMetadataJSON: statement.string(8),
            backupAvailable: (statement.int(9) ?? 0) != 0,
            errorMessage: statement.string(10),
            createdAt: Date(timeIntervalSince1970: statement.double(11) ?? 0),
            completedAt: statement.double(12).map(Date.init(timeIntervalSince1970:))
        )
    }
}

