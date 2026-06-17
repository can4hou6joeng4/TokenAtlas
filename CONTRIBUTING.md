# Contributing

Thanks for helping improve TokenAtlas. This repository is intended to stay
small, readable, and reproducible.

## Local Setup

Clone with submodules:

```bash
git clone --recursive https://github.com/can4hou6joeng4/TokenAtlas.git
cd TokenAtlas
```

Install XcodeGen:

```bash
brew install xcodegen
```

Run the app from the canonical debug build path:

```bash
bash scripts/run-debug.sh
```

Do not launch development builds with `open -a TokenAtlas`; this menu-bar app
can conflict with other bundles that share the same bundle identifier.

## Before Opening a Pull Request

Run the relevant checks:

```bash
bash scripts/run-tests.sh
```

For app behavior or UI changes, also run:

```bash
bash scripts/run-debug.sh
```

Keep pull requests focused on one topic. Include screenshots or short screen
recordings for visible UI changes, and document any new permissions, network
calls, or release workflow changes.

## Code Style

- Follow the existing SwiftUI and service boundaries.
- Keep provider-specific parsing under `TokenAtlas/Providers/<Provider>/`.
- Keep shared formatting, summaries, and charts in common app layers.
- Use `Log` for runtime logging rather than `print`.
- Avoid adding dependencies unless the maintenance cost is clearly justified.

## Questions & Discussions

- Ideas, questions, and "is this a bug or expected?" → [GitHub Discussions](https://github.com/can4hou6joeng4/TokenAtlas/discussions).
- Reproducible bugs and concrete feature requests → [Issues](https://github.com/can4hou6joeng4/TokenAtlas/issues) (please use the templates).
- Security reports → see [SECURITY.md](SECURITY.md); do not open a public issue for vulnerabilities.
