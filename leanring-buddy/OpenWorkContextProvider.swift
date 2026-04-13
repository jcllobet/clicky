//
//  OpenWorkContextProvider.swift
//  leanring-buddy
//
//  Loads a bounded subset of the local OpenWork repo so Clicky can answer
//  OpenWork-specific questions with more context than the screenshot alone.
//

import Foundation

final class OpenWorkContextProvider {
    private struct CuratedOpenWorkContextFile {
        let relativePath: String
        let maximumCharacterCount: Int
    }

    private static let openWorkContextDirectoryPathInfoKey = "OpenWorkContextDirectoryPath"
    private static let maximumCombinedCharacterCount = 16_000
    private static let curatedOpenWorkContextFiles: [CuratedOpenWorkContextFile] = [
        .init(relativePath: "AGENTS.md", maximumCharacterCount: 2_500),
        .init(relativePath: "ARCHITECTURE.md", maximumCharacterCount: 5_500),
        .init(relativePath: "PRODUCT.md", maximumCharacterCount: 1_800),
        .init(relativePath: "README.md", maximumCharacterCount: 2_200),
        .init(relativePath: "package.json", maximumCharacterCount: 900),
        .init(relativePath: "pnpm-workspace.yaml", maximumCharacterCount: 200),
        .init(relativePath: "turbo.json", maximumCharacterCount: 500),
        .init(relativePath: "apps/app/package.json", maximumCharacterCount: 900),
        .init(relativePath: "apps/desktop/package.json", maximumCharacterCount: 600)
    ]

    private let fileManager = FileManager.default
    private var hasLoggedContextLoadSuccess = false
    private var hasLoggedMissingRepositoryWarning = false

    func makePromptContext() -> String? {
        guard let openWorkRepositoryDirectoryURL = resolveOpenWorkRepositoryDirectoryURL() else {
            return nil
        }

        var contextSections = [
            """
            local openwork repo context:
            - use this only when the user's question is about openwork, how openwork works, or where something lives in the openwork repo.
            - this context is intentionally bounded to a fixed short list of files from the local checkout at \(openWorkRepositoryDirectoryURL.path).
            - if the user's question is unrelated to openwork, ignore this section completely.
            """
        ]

        var combinedCharacterCount = contextSections.joined(separator: "\n\n").count
        var loadedFileCount = 0

        for curatedOpenWorkContextFile in Self.curatedOpenWorkContextFiles {
            guard let openWorkFileSection = makeOpenWorkFileSection(
                for: curatedOpenWorkContextFile,
                openWorkRepositoryDirectoryURL: openWorkRepositoryDirectoryURL
            ) else {
                continue
            }

            let remainingCharacterCount = Self.maximumCombinedCharacterCount - combinedCharacterCount
            guard remainingCharacterCount > 0 else {
                break
            }

            let boundedOpenWorkFileSection = trimmedContents(
                openWorkFileSection,
                maximumCharacterCount: remainingCharacterCount
            )

            contextSections.append(boundedOpenWorkFileSection)
            combinedCharacterCount += boundedOpenWorkFileSection.count + 2
            loadedFileCount += 1
        }

        guard loadedFileCount > 0 else {
            return nil
        }

        if !hasLoggedContextLoadSuccess {
            hasLoggedContextLoadSuccess = true
            print("📚 OpenWork context loaded from \(openWorkRepositoryDirectoryURL.path) using \(loadedFileCount) curated file(s)")
        }

        return contextSections.joined(separator: "\n\n")
    }

    private func makeOpenWorkFileSection(
        for curatedOpenWorkContextFile: CuratedOpenWorkContextFile,
        openWorkRepositoryDirectoryURL: URL
    ) -> String? {
        let openWorkFileURL = openWorkRepositoryDirectoryURL.appendingPathComponent(curatedOpenWorkContextFile.relativePath)

        guard let openWorkFileContents = try? String(contentsOf: openWorkFileURL, encoding: .utf8) else {
            return nil
        }

        let trimmedOpenWorkFileContents = trimmedContents(
            openWorkFileContents,
            maximumCharacterCount: curatedOpenWorkContextFile.maximumCharacterCount
        )

        return """
        file: \(curatedOpenWorkContextFile.relativePath)
        \(trimmedOpenWorkFileContents)
        """
    }

    private func resolveOpenWorkRepositoryDirectoryURL() -> URL? {
        let candidateRepositoryDirectoryURLs = makeCandidateRepositoryDirectoryURLs()

        for candidateRepositoryDirectoryURL in candidateRepositoryDirectoryURLs {
            let agentsFileURL = candidateRepositoryDirectoryURL.appendingPathComponent("AGENTS.md")
            if fileManager.fileExists(atPath: agentsFileURL.path) {
                return candidateRepositoryDirectoryURL
            }
        }

        if !hasLoggedMissingRepositoryWarning {
            hasLoggedMissingRepositoryWarning = true
            let attemptedPaths = candidateRepositoryDirectoryURLs.map(\.path).joined(separator: ", ")
            print("⚠️ OpenWork context unavailable. Tried: \(attemptedPaths)")
        }

        return nil
    }

    private func makeCandidateRepositoryDirectoryURLs() -> [URL] {
        var candidateRepositoryDirectoryURLs: [URL] = []

        if let configuredDirectoryPath = AppBundleConfiguration.stringValue(forKey: Self.openWorkContextDirectoryPathInfoKey) {
            candidateRepositoryDirectoryURLs.append(urlForPotentialDirectoryPath(configuredDirectoryPath))
        }

        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        var searchDirectoryURL = currentDirectoryURL

        for _ in 0..<5 {
            candidateRepositoryDirectoryURLs.append(
                searchDirectoryURL.appendingPathComponent("references/openwork", isDirectory: true)
            )
            searchDirectoryURL.deleteLastPathComponent()
        }

        var deduplicatedRepositoryDirectoryURLs: [URL] = []
        var seenPaths = Set<String>()

        for candidateRepositoryDirectoryURL in candidateRepositoryDirectoryURLs {
            if seenPaths.insert(candidateRepositoryDirectoryURL.path).inserted {
                deduplicatedRepositoryDirectoryURLs.append(candidateRepositoryDirectoryURL)
            }
        }

        return deduplicatedRepositoryDirectoryURLs
    }

    private func urlForPotentialDirectoryPath(_ potentialDirectoryPath: String) -> URL {
        let expandedDirectoryPath = NSString(string: potentialDirectoryPath).expandingTildeInPath

        if NSString(string: expandedDirectoryPath).isAbsolutePath {
            return URL(fileURLWithPath: expandedDirectoryPath, isDirectory: true)
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expandedDirectoryPath, isDirectory: true)
    }

    private func trimmedContents(_ contents: String, maximumCharacterCount: Int) -> String {
        let normalizedContents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncationIndicator = "\n... [truncated]"

        guard normalizedContents.count > maximumCharacterCount else {
            return normalizedContents
        }

        guard maximumCharacterCount > truncationIndicator.count else {
            return String(normalizedContents.prefix(maximumCharacterCount))
        }

        let truncatedCharacterCount = maximumCharacterCount - truncationIndicator.count
        let truncatedEndIndex = normalizedContents.index(
            normalizedContents.startIndex,
            offsetBy: truncatedCharacterCount
        )

        return String(normalizedContents[..<truncatedEndIndex]) + truncationIndicator
    }
}
