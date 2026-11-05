import Foundation
import Testing
@testable import BoardKit

@Suite("Material themes")
struct ThemeDesignTests {
    static let additions: [ThemeID] = [.chalkboard, .fieldNotes, .crimeLab, .circuit, .scrapbook, .newsroom, .observatory]

    @Test func newThemesDifferInStructureRatherThanJustColor() {
        let themes = Self.additions
        #expect(themes.count == 7)
        #expect(Set(themes.map(\.texture)).count == 7)
        #expect(Set(themes.map { $0.design.ornament }).count == 7)
        #expect(Set(themes.map { $0.design.font }).count == 7)
        #expect(Set(themes.map { $0.design.fastener }).count == 7)
        #expect(Set(themes.map { $0.design.connection }).count == 7)
        #expect(Set(themes.map { $0.design.label }).count == 7)
        #expect(Set(themes.map { $0.design.photoMount }).count == 7)
        #expect(themes.allSatisfy { $0.design != .standard && $0.design.webMeshOpacity < 0.2 })
    }

    @Test func retiredVariantsMigrateWithoutRemainingInThePicker() throws {
        #expect(!ThemeID.allCases.map(\.rawValue).contains("forest"))
        #expect(!ThemeID.allCases.map(\.rawValue).contains("midnight"))
        for (old, expected) in [("forest", ThemeID.fieldNotes), ("midnight", .observatory)] {
            let data = Data("{\"format\":\"evidenceboard\",\"theme\":\"\(old)\"}".utf8)
            let loaded = try BoardCodec.decode(data)
            #expect(loaded.board.theme == expected)
            #expect(loaded.report == LoadReport())
            let saved = try BoardCodec.encode(loaded.board)
            #expect(try BoardCodec.decode(saved).board.theme == expected)
        }
    }

    @Test(arguments: ThemeID.allCases)
    func everyThemeSavesAndReopens(_ theme: ThemeID) throws {
        var board = Board.new()
        board.theme = theme
        let loaded = try BoardCodec.decode(BoardCodec.encode(board))
        #expect(loaded.board == board)
        #expect(loaded.report == LoadReport())
    }
}
