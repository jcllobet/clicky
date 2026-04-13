//
//  OpenWorkContextProvider.swift
//  leanring-buddy
//
//  Loads a bounded subset of the local OpenWork repo so Clicky can answer
//  OpenWork-specific questions with more context than the screenshot alone.
//

import Foundation

final class OpenWorkContextProvider {
    private struct CuratedOpenWorkContextSection {
        let label: String
        let relativePath: String
        let maximumCharacterCount: Int
        let lineRange: ClosedRange<Int>?
    }

    private static let openWorkContextDirectoryPathInfoKey = "OpenWorkContextDirectoryPath"
    private static let maximumCombinedCharacterCount = 30_000
    private static let curatedOpenWorkContextSections: [CuratedOpenWorkContextSection] = [
        .init(
            label: "openwork overview",
            relativePath: "AGENTS.md",
            maximumCharacterCount: 2_200,
            lineRange: 1...120
        ),
        .init(
            label: "openwork architecture",
            relativePath: "ARCHITECTURE.md",
            maximumCharacterCount: 3_400,
            lineRange: 157...280
        ),
        .init(
            label: "openwork product",
            relativePath: "PRODUCT.md",
            maximumCharacterCount: 1_200,
            lineRange: 1...80
        ),
        .init(
            label: "desktop route handling and settings tabs",
            relativePath: "apps/app/src/app/app.tsx",
            maximumCharacterCount: 1_800,
            lineRange: 2326...2385
        ),
        .init(
            label: "settings available tabs",
            relativePath: "apps/app/src/app/pages/settings.tsx",
            maximumCharacterCount: 1_300,
            lineRange: 824...875
        ),
        .init(
            label: "settings tab descriptions",
            relativePath: "apps/app/src/app/pages/settings.tsx",
            maximumCharacterCount: 1_300,
            lineRange: 1347...1405
        ),
        .init(
            label: "settings reveal workspace config action",
            relativePath: "apps/app/src/app/pages/settings.tsx",
            maximumCharacterCount: 900,
            lineRange: 1212...1235
        ),
        .init(
            label: "english settings tab labels and descriptions",
            relativePath: "apps/app/src/i18n/locales/en.ts",
            maximumCharacterCount: 1_200,
            lineRange: 1670...1685
        ),
        .init(
            label: "english cloud settings labels",
            relativePath: "apps/app/src/i18n/locales/en.ts",
            maximumCharacterCount: 2_500,
            lineRange: 399...485
        ),
        .init(
            label: "skills page actions and filters",
            relativePath: "apps/app/src/app/pages/skills.tsx",
            maximumCharacterCount: 1_600,
            lineRange: 640...710
        ),
        .init(
            label: "authorized folders panel",
            relativePath: "apps/app/src/app/app-settings/authorized-folders-panel.tsx",
            maximumCharacterCount: 2_500,
            lineRange: 1...240
        ),
        .init(
            label: "reveal workspace in finder",
            relativePath: "apps/app/src/app/pages/session.tsx",
            maximumCharacterCount: 900,
            lineRange: 1030...1054
        ),
        .init(
            label: "reveal skills folder",
            relativePath: "apps/app/src/app/context/extensions.ts",
            maximumCharacterCount: 1_100,
            lineRange: 1745...1778
        ),
        .init(
            label: "remote workspace connect flow",
            relativePath: "packages/docs/get-started.mdx",
            maximumCharacterCount: 1_300,
            lineRange: 1...80
        ),
        .init(
            label: "cloud sign in and active org flow",
            relativePath: "packages/docs/get-started-cloud.mdx",
            maximumCharacterCount: 1_500,
            lineRange: 1...80
        ),
        .init(
            label: "cloud shared workspace flow",
            relativePath: "packages/docs/cloud-shared-workspaces.mdx",
            maximumCharacterCount: 1_200,
            lineRange: 1...80
        ),
        .init(
            label: "importing skills flow",
            relativePath: "packages/docs/importing-a-skill.mdx",
            maximumCharacterCount: 1_600,
            lineRange: 1...70
        ),
        .init(
            label: "cloud skill hub flow",
            relativePath: "packages/docs/cloud-skill-hubs.mdx",
            maximumCharacterCount: 1_500,
            lineRange: 1...90
        )
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
            local openwork repo and navigation context:
            - use this when the user's question is about openwork, how openwork works, where something lives in the repo, how to navigate the openwork app, how to complete onboarding or settings flows, or how to access workspace-related files in finder.
            - screenshots still matter most for the current visible controls. use the repo-backed snippets below to infer which openwork surface the user is on, what nearby controls are likely clickable, and what next screen or tab they need.
            - this context is intentionally bounded to a fixed short list of repo snippets from the local checkout at \(openWorkRepositoryDirectoryURL.path).
            - if the user's question is unrelated to openwork, ignore this section completely.
            """
        ]

        var combinedCharacterCount = contextSections.joined(separator: "\n\n").count
        var loadedSectionCount = 0

        for curatedOpenWorkContextSection in Self.curatedOpenWorkContextSections {
            guard let openWorkContextSection = makeOpenWorkContextSection(
                for: curatedOpenWorkContextSection,
                openWorkRepositoryDirectoryURL: openWorkRepositoryDirectoryURL
            ) else {
                continue
            }

            let remainingCharacterCount = Self.maximumCombinedCharacterCount - combinedCharacterCount
            guard remainingCharacterCount > 0 else {
                break
            }

            let boundedOpenWorkContextSection = trimmedContents(
                openWorkContextSection,
                maximumCharacterCount: remainingCharacterCount
            )

            contextSections.append(boundedOpenWorkContextSection)
            combinedCharacterCount += boundedOpenWorkContextSection.count + 2
            loadedSectionCount += 1
        }

        guard loadedSectionCount > 0 else {
            return nil
        }

        if !hasLoggedContextLoadSuccess {
            hasLoggedContextLoadSuccess = true
            print("📚 OpenWork context loaded from \(openWorkRepositoryDirectoryURL.path) using \(loadedSectionCount) curated section(s)")
        }

        return contextSections.joined(separator: "\n\n")
    }

    private func makeOpenWorkContextSection(
        for curatedOpenWorkContextSection: CuratedOpenWorkContextSection,
        openWorkRepositoryDirectoryURL: URL
    ) -> String? {
        let openWorkFileURL = openWorkRepositoryDirectoryURL.appendingPathComponent(curatedOpenWorkContextSection.relativePath)

        guard let fullOpenWorkFileContents = try? String(contentsOf: openWorkFileURL, encoding: .utf8) else {
            return nil
        }

        let selectedOpenWorkFileContents = selectedContents(
            from: fullOpenWorkFileContents,
            lineRange: curatedOpenWorkContextSection.lineRange
        )

        let trimmedOpenWorkFileContents = trimmedContents(
            selectedOpenWorkFileContents,
            maximumCharacterCount: curatedOpenWorkContextSection.maximumCharacterCount
        )

        let lineRangeLabel: String = {
            guard let lineRange = curatedOpenWorkContextSection.lineRange else {
                return ""
            }
            return " lines \(lineRange.lowerBound)-\(lineRange.upperBound)"
        }()

        return """
        section: \(curatedOpenWorkContextSection.label)
        source: \(curatedOpenWorkContextSection.relativePath)\(lineRangeLabel)
        \(trimmedOpenWorkFileContents)
        """
    }

    private func selectedContents(from fullContents: String, lineRange: ClosedRange<Int>?) -> String {
        guard let lineRange else {
            return fullContents
        }

        let fileLines = fullContents.components(separatedBy: .newlines)
        guard !fileLines.isEmpty else {
            return fullContents
        }

        let safeStartLine = max(1, min(lineRange.lowerBound, fileLines.count))
        let safeEndLine = max(safeStartLine, min(lineRange.upperBound, fileLines.count))
        let selectedLines = fileLines[(safeStartLine - 1)...(safeEndLine - 1)]
        return selectedLines.joined(separator: "\n")
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
