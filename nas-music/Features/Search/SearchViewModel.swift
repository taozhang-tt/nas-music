//
//  SearchViewModel.swift
//  nas-music
//

import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var keyword = ""
    @Published private(set) var state: SearchViewState = .idle

    private let providerStore: MusicLibraryProviderStore
    private var searchTask: Task<Void, Never>?
    private var keywordCancellable: AnyCancellable?

    init(providerStore: MusicLibraryProviderStore) {
        self.providerStore = providerStore
        keywordCancellable = $keyword
            .removeDuplicates()
            .sink { [weak self] keyword in
                self?.scheduleSearch(keyword: keyword)
            }
    }

    deinit {
        searchTask?.cancel()
    }

    private func scheduleSearch(keyword: String) {
        searchTask?.cancel()
        let normalized = SearchTextNormalizer.normalize(keyword)
        guard !normalized.isEmpty else {
            state = .idle
            return
        }

        state = .searching
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, let self else { return }
                let result = try await self.providerStore.activeProvider.search(keyword: normalized)
                guard !Task.isCancelled else { return }
                self.state = result.isEmpty ? .empty : .loaded(result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.state = .failed(message: Self.message(for: error))
            }
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "搜索失败，请稍后重试。"
    }
}
