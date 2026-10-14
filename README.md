# Evidence Board

A native macOS app for building detective-style evidence boards. You place **text**, **images** and **webpages** on an infinite free canvas and connect the dots with red string. Each board is saved as a single, portable **JSON** file.

- 📐 **Full design document:** [`docs/DESIGN.md`](docs/DESIGN.md)
- 🧾 **File format schema:** [`docs/schema/evidenceboard.schema.json`](docs/schema/evidenceboard.schema.json)
- 🗂 **Sample board:** [`docs/examples/harbor-case.evboard`](docs/examples/harbor-case.evboard)

## Highlights

- A free, infinite canvas that stays at 120 fps (Core Animation engine, culling, level of detail)
- Only three card types: Text, Image and Web
- Rich, gradient-driven link previews built from each page's own color palette
- Physical-looking strings with sag, labels, and **Focus** and **Trace** modes to follow connections
- Four themes: Noir (default), Cork, Blueprint and Daylight, with Liquid Glass on macOS 26
- `.evboard` is plain JSON. Images and link snapshots are embedded, so a board opens offline exactly as you saved it

Built with Swift 6, SwiftUI, AppKit and Core Animation in Xcode, targeting macOS 15 and later.
