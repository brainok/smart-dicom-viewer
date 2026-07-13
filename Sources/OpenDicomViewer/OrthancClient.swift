// OrthancClient.swift
// OpenDicomViewer
//
// Small REST client for browsing and downloading DICOM studies from an
// Orthanc server on the local network.

import Foundation

struct OrthancConnection: Equatable {
    let baseURL: URL
    let username: String
    let password: String

    var hasCredentials: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func make(serverAddress: String, username: String, password: String) throws -> OrthancConnection {
        let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OrthancClientError.invalidServerAddress }

        let normalized = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: normalized), let scheme = url.scheme, let host = url.host,
              ["http", "https"].contains(scheme.lowercased()), !host.isEmpty else {
            throw OrthancClientError.invalidServerAddress
        }

        return OrthancConnection(
            baseURL: url,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }
}

struct OrthancStudy: Identifiable, Equatable {
    let id: String
    let patientName: String
    let patientID: String
    let studyDescription: String
    let studyDate: String
    let accessionNumber: String
    let seriesCount: Int

    var displayTitle: String {
        let desc = studyDescription.isEmpty ? "Untitled Study" : studyDescription
        return patientName.isEmpty ? desc : "\(patientName) - \(desc)"
    }

    var displaySubtitle: String {
        var parts: [String] = []
        if !patientID.isEmpty { parts.append("ID \(patientID)") }
        if !studyDate.isEmpty { parts.append(formattedStudyDate(studyDate)) }
        if !accessionNumber.isEmpty { parts.append("Acc \(accessionNumber)") }
        parts.append("\(seriesCount) Series")
        return parts.joined(separator: "  |  ")
    }

    private func formattedStudyDate(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count == 8 else { return value }
        let year = digits.prefix(4)
        let monthStart = digits.index(digits.startIndex, offsetBy: 4)
        let dayStart = digits.index(digits.startIndex, offsetBy: 6)
        return "\(year)-\(digits[monthStart..<dayStart])-\(digits[dayStart..<digits.endIndex])"
    }
}

enum OrthancClientError: LocalizedError {
    case invalidServerAddress
    case invalidResponse
    case httpStatus(Int, String)
    case noInstances

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress:
            return "Enter a valid Orthanc address, for example 192.168.0.10:8042."
        case .invalidResponse:
            return "The Orthanc server returned an unexpected response."
        case let .httpStatus(status, message):
            if message.isEmpty {
                return "Orthanc request failed with HTTP \(status)."
            }
            return "Orthanc request failed with HTTP \(status): \(message)"
        case .noInstances:
            return "The selected study has no downloadable DICOM instances."
        }
    }
}

final class OrthancClient {
    private let connection: OrthancConnection
    private let session: URLSession

    init(connection: OrthancConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    func fetchStudies() async throws -> [OrthancStudy] {
        let payload = try await requestData(path: "/studies", queryItems: [URLQueryItem(name: "expand", value: "")])
        guard let array = try JSONSerialization.jsonObject(with: payload) as? [Any] else {
            throw OrthancClientError.invalidResponse
        }

        var studies: [OrthancStudy] = []
        for item in array {
            if let dictionary = item as? [String: Any],
               let study = parseStudy(dictionary) {
                studies.append(study)
            } else if let id = item as? String {
                let detailData = try await requestData(path: "/studies/\(id)")
                if let dictionary = try JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                   let study = parseStudy(dictionary, fallbackID: id) {
                    studies.append(study)
                }
            }
        }

        return studies.sorted {
            if $0.studyDate != $1.studyDate { return $0.studyDate > $1.studyDate }
            return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    func downloadStudy(_ study: OrthancStudy, progress: @escaping @MainActor (Double, String) -> Void) async throws -> URL {
        let instanceIDs = try await fetchInstanceIDs(studyID: study.id)
        guard !instanceIDs.isEmpty else { throw OrthancClientError.noInstances }

        let directory = makeDownloadDirectory(study: study)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, instanceID) in instanceIDs.enumerated() {
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent("\(index + 1)-\(safeFilename(instanceID)).dcm")
            try await downloadInstance(instanceID: instanceID, to: destination)
            let fraction = Double(index + 1) / Double(instanceIDs.count)
            await progress(fraction, "Downloaded \(index + 1) / \(instanceIDs.count)")
        }

        return directory
    }

    private func fetchInstanceIDs(studyID: String) async throws -> [String] {
        let payload = try await requestData(path: "/studies/\(studyID)/instances")
        guard let array = try JSONSerialization.jsonObject(with: payload) as? [Any] else {
            throw OrthancClientError.invalidResponse
        }
        let initialIDs = parseIDs(array)
        if !initialIDs.isEmpty { return initialIDs }

        let detailData = try await requestData(path: "/studies/\(studyID)")
        guard let detail = try JSONSerialization.jsonObject(with: detailData) as? [String: Any] else {
            throw OrthancClientError.invalidResponse
        }

        let seriesIDs = ids(from: detail["Series"])
        var instanceIDs: [String] = []
        for seriesID in seriesIDs {
            let seriesData = try await requestData(path: "/series/\(seriesID)/instances")
            if let seriesArray = try JSONSerialization.jsonObject(with: seriesData) as? [Any] {
                instanceIDs.append(contentsOf: parseIDs(seriesArray))
            }
        }
        return instanceIDs
    }

    private func downloadInstance(instanceID: String, to destination: URL) async throws {
        let request = makeRequest(path: "/instances/\(instanceID)/file")
        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response: response, payload: nil)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private func requestData(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let request = makeRequest(path: path, queryItems: queryItems)
        let (payload, response) = try await session.data(for: request)
        try validate(response: response, payload: payload)
        return payload
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: connection.baseURL, resolvingAgainstBaseURL: false)!
        components.path = joinedPath(basePath: components.path, path: path)
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        if connection.hasCredentials {
            let token = "\(connection.username):\(connection.password)"
                .data(using: .utf8)?
                .base64EncodedString() ?? ""
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func joinedPath(basePath: String, path: String) -> String {
        let trimmedBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedBase.isEmpty { return "/\(trimmedPath)" }
        if trimmedPath.isEmpty { return "/\(trimmedBase)" }
        return "/\(trimmedBase)/\(trimmedPath)"
    }

    private func validate(response: URLResponse, payload: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OrthancClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = payload.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw OrthancClientError.httpStatus(http.statusCode, message)
        }
    }

    private func parseStudy(_ dictionary: [String: Any], fallbackID: String? = nil) -> OrthancStudy? {
        guard let id = dictionary["ID"] as? String ?? fallbackID else { return nil }
        let mainTags = dictionary["MainDicomTags"] as? [String: Any] ?? [:]
        let patientTags = dictionary["PatientMainDicomTags"] as? [String: Any] ?? [:]
        let seriesCount = ids(from: dictionary["Series"]).count

        return OrthancStudy(
            id: id,
            patientName: string(patientTags["PatientName"]),
            patientID: string(patientTags["PatientID"]),
            studyDescription: string(mainTags["StudyDescription"]),
            studyDate: string(mainTags["StudyDate"]),
            accessionNumber: string(mainTags["AccessionNumber"]),
            seriesCount: seriesCount
        )
    }

    private func parseIDs(_ array: [Any]) -> [String] {
        array.flatMap { ids(from: $0) }
    }

    private func ids(from value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let string = value as? String { return [string] }
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries.compactMap { string($0["ID"]) }
        }
        if let dictionary = value as? [String: Any] {
            let id = string(dictionary["ID"])
            guard !id.isEmpty else { return [] }
            return [id]
        }
        if let array = value as? [Any] {
            return array.flatMap { ids(from: $0) }
        }
        return []
    }

    private func string(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func makeDownloadDirectory(study: OrthancStudy) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartDICOMViewer-Orthanc", isDirectory: true)
        let nameBits = [
            study.patientName,
            study.studyDescription,
            study.studyDate,
            study.id,
            String(Int(Date().timeIntervalSince1970))
        ].filter { !$0.isEmpty }
        let name = safeFilename(nameBits.joined(separator: "-"))
        return root.appendingPathComponent(name, isDirectory: true)
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }
}
