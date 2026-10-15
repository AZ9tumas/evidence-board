import Foundation
import Testing
import BoardKit
@testable import LinkPreviewKit

/// One saved page head, with what the pipeline should make of it in a leading comment.
struct SiteFixture: CustomTestStringConvertible, Sendable {
    let name: String
    let html: String
    let url: URL
    let expectation: [String: JSONValue]

    var testDescription: String { name }

    /// `Tests/Fixtures/sites`, found from this file so it works without bundle resources.
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent() // LinkPreviewKitTests
        .deletingLastPathComponent() // Tests
        .appending(path: "Fixtures/sites")

    static func all() throws -> [SiteFixture] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "html" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { file in
            let html = try String(contentsOf: file, encoding: .utf8)
            guard let open = html.range(of: "<!-- "), let close = html.range(of: " -->") else {
                throw FixtureError.missingExpectation(file.lastPathComponent)
            }
            let json = Data(html[open.upperBound..<close.lowerBound].utf8)
            let expectation = try JSONDecoder().decode([String: JSONValue].self, from: json)
            guard case .string(let address) = expectation["url"], let url = URL(string: address) else {
                throw FixtureError.missingExpectation(file.lastPathComponent)
            }
            return SiteFixture(name: file.deletingPathExtension().lastPathComponent, html: html, url: url, expectation: expectation)
        }
    }

    func string(_ key: String) -> String? {
        if case .string(let value) = expectation[key] { return value }
        return nil
    }

    func number(_ key: String) -> Double? {
        if case .number(let value) = expectation[key] { return value }
        return nil
    }

    /// The size of the image the page's best candidate downloads as; `nil` when there's
    /// none or it fails to download.
    var imageSize: PixelSize? {
        guard case .array(let values) = expectation["image"], values.count == 2,
              case .number(let width) = values[0], case .number(let height) = values[1] else { return nil }
        return PixelSize(width: Int(width), height: Int(height))
    }

    enum FixtureError: Error {
        case missingExpectation(String)
    }
}

/// Just enough JSON to read fixture expectations.
enum JSONValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case array([JSONValue])
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }
}

@Suite("Site fixtures")
struct SiteFixtureTests {
    @Test func thereAreAtLeastSixty() throws {
        #expect(try SiteFixture.all().count >= 60)
    }

    @Test(arguments: try SiteFixture.all())
    func pipelineMatchesExpectations(_ fixture: SiteFixture) throws {
        let head = HTMLHeadParser.parse(fixture.html, baseURL: fixture.url)
        let info = MetadataMerger.merge(head, url: fixture.url)
        let variant = VariantRules.variant(for: info.kind, image: fixture.imageSize)

        if let expected = fixture.string("variant") {
            #expect(variant.rawValue == expected)
        }
        if let expected = fixture.string("title") {
            #expect((info.title ?? LinkURL.displayHost(of: fixture.url)) == expected)
        }
        if let expected = fixture.string("siteName") {
            #expect(info.siteName == expected)
        }
        if let expected = fixture.string("author") {
            #expect(info.author == expected)
        }
        if let expected = fixture.number("duration") {
            #expect(info.duration == expected)
        }
        if let expected = fixture.string("imageURL") {
            #expect(info.images.first?.url.absoluteString == expected)
        }
        if let expected = fixture.string("iconURL") {
            #expect(info.icons.first?.url.absoluteString == expected)
        }
        if let expected = fixture.string("themeColor") {
            #expect(info.themeColor == expected)
        }
        // Nothing from the body may leak in.
        #expect(info.title != "Decoy in body")
        #expect(!(info.title ?? "").contains("Decoy"))
    }
}
