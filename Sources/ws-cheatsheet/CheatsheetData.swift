import Foundation

/// Wire shape of ~/.config/workspace/cheatsheet.json.
///
/// The document is a section pool + a list of named lenses (views). Each
/// view declares its own 3-column layout by referencing section ids from
/// the pool. The renderer picks one view at a time; the user toggles
/// between views with number keys / Tab in the HUD.
///
/// Design rationale:
/// - Sections written once → no drift when the same binding appears in
///   multiple lenses.
/// - Per-view column layout → hand-tuned visual balance per lens.
/// - "Default + learning category" model: the first two columns are
///   typically AeroSpace bindings (stay frozen); column 2 changes per
///   view. Reduces eye travel when toggling between lenses.
///
/// The decoder is permissive about extra keys (anything starting with
/// `_` is ignored) so the layout file's `_doc` annotations don't blow up
/// older binaries.
struct CheatsheetDocument: Decodable {
    let banner: [BannerItem]
    let views: [Lens]
    let sections: [String: Section]

    init(banner: [BannerItem], views: [Lens], sections: [String: Section]) {
        self.banner = banner
        self.views = views
        self.sections = sections
    }

    struct BannerItem: Decodable {
        let k: String
        let v: String

        init(k: String, v: String) {
            self.k = k
            self.v = v
        }
    }

    /// A named view over the section pool. `key` is the single-character
    /// chord the user presses inside the HUD to jump to this lens.
    struct Lens: Decodable, Identifiable {
        let id: String
        let label: String
        let key: String
        let columns: [Column]

        init(id: String, label: String, key: String, columns: [Column]) {
            self.id = id
            self.label = label
            self.key = key
            self.columns = columns
        }
    }

    /// One vertical column in a lens. References sections by id; the
    /// renderer never iterates `Column` directly — it resolves through
    /// `CheatsheetDocument.resolve(view:)` into `ResolvedColumn`, which
    /// carries the `ForEach` identity.
    struct Column: Decodable {
        let sections: [String]

        init(sections: [String]) {
            self.sections = sections
        }
    }

    struct Section: Decodable, Identifiable {
        let title: String
        let rows: [[String]]      // wire is [["key", "desc"], ...]

        /// Optional `color` (legacy hex per-section) and `family`
        /// (preferred Catppuccin token). `family` wins via
        /// `FamilyColors.resolve`; `color` is the v1-back-compat fallback.
        let color: String?
        let family: String?

        /// Small subtitle line under the title (e.g. "aerospace · ws-prompt").
        let sub: String?

        /// Optional one-line "mental model" caption — italicized below
        /// the subtitle. Sweller's worked-example move: tell the reader
        /// what the section is about before showing the keys.
        let idea: String?

        /// Opt-in to a non-table body. The only recognized value is
        /// `"keyboard"`, which routes the section through
        /// `SpatialKeyboardView`. No shipped section sets it today —
        /// the hook is available to any data that opts in.
        let customLayout: String?

        var id: String { title }

        init(
            title: String,
            rows: [[String]],
            color: String? = nil,
            family: String? = nil,
            sub: String? = nil,
            idea: String? = nil,
            customLayout: String? = nil
        ) {
            self.title = title
            self.rows = rows
            self.color = color
            self.family = family
            self.sub = sub
            self.idea = idea
            self.customLayout = customLayout
        }
    }

    /// One column with its section ids resolved into Section values.
    /// Renderer-facing shape — produced by `resolve(view:)`.
    struct ResolvedColumn: Identifiable {
        let id: String
        let sections: [Section]
    }

    /// Resolve a lens's column → section-id references into the actual
    /// Section values from the pool. Missing ids are silently dropped
    /// (the lens still renders; the gap is a visible hint to the
    /// editor).
    func resolve(view: Lens) -> [ResolvedColumn] {
        view.columns.enumerated().map { idx, col in
            ResolvedColumn(
                id: "\(view.id)-\(idx)",
                sections: col.sections.compactMap { sections[$0] }
            )
        }
    }
}

enum CheatsheetLoader {
    static let defaultPath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/workspace/cheatsheet.json")

    static func load(from url: URL = defaultPath) throws -> CheatsheetDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(CheatsheetDocument.self, from: data)
    }
}
