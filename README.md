# Plantoir

Write your course notes as Markdown in [Obsidian](https://obsidian.md); Plantoir
turns them into a polished, searchable website for each of your class sections —
previewed privately on your own computer, published when you say so.

## Teachers

**Everything you need is at [plantoir.app](https://plantoir.app)** — downloads
for macOS and Windows, a tour of what Plantoir does, and instructions written
for teachers, not developers. The apps install and run without administrator
rights, so they work on managed school computers.

You do not need anything from this repository to use Plantoir.

## Developers

This repository holds the complete sources: the macOS app (SwiftUI), the
Windows app (.NET 9 / WinUI 3), the shared Python toolchain both apps drive,
and the container recipe that builds each site with a patched
[Quartz](https://github.com/jackyzha0/quartz) v4.5.0.

You are welcome to fork it and make it your own. Start with
[CLAUDE.md](CLAUDE.md) — the single entry point: setup on a new machine (the
Xcode project is generated, not committed), what gates what, the conventions
this repository follows, and where everything else lives. The deep dives are
in [`documentation/`](documentation/README.md).

## History

Plantoir began as a workshop at the 2025 CEMC Summer Conference for Computer
Studies and Mathematics Educators. The original workshop document is preserved
as [PRESENTATION.md](PRESENTATION.md).

## Credits

- [Quartz](https://github.com/jackyzha0/quartz) by [Jacky Zhao](https://jzhao.xyz/)
- Plantoir by [Russell Gordon](https://github.com/russellgordon)

## License

MIT License. Use, remix, and share freely — especially with other educators.
