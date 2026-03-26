# Contributing to Data-X

Thank you for your interest in contributing to Data-X!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/data-x.git`
3. Create a branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Test your changes
6. Commit: `git commit -m "feat: add your feature"`
7. Push: `git push origin feature/your-feature`
8. Open a Pull Request

## Development Setup

### Prerequisites

- Rust 1.70+
- Node.js 18+
- npm or yarn

### Building

```bash
# Install frontend dependencies
cd ui && npm install && cd ..

# Development mode (hot reload)
cd ui && npm run tauri dev

# Production build
cargo tauri build

# TUI only (faster compile)
cargo build --release --no-default-features
```

### Project Structure

```
data-x/
├── src/              # Rust TUI source
├── src-tauri/        # Tauri backend
│   └── src/
│       ├── commands.rs  # IPC commands
│       ├── scanner.rs   # Directory scanner
│       └── types.rs     # Data types
├── ui/               # React frontend
│   └── src/
│       ├── components/  # React components
│       └── App.tsx      # Main app
└── scripts/          # Build scripts
```

## Code Style

- **Rust**: Follow standard Rust conventions, run `cargo fmt` and `cargo clippy`
- **TypeScript**: Use Prettier and ESLint
- **Commits**: Use [Conventional Commits](https://www.conventionalcommits.org/)
  - `feat:` new feature
  - `fix:` bug fix
  - `docs:` documentation
  - `refactor:` code refactoring
  - `test:` tests
  - `chore:` maintenance

## Testing

```bash
# Rust tests
cargo test

# Frontend tests
cd ui && npm test
```

## Reporting Issues

- Search existing issues first
- Include OS version, Data-X version
- Provide steps to reproduce
- Include error messages/screenshots

## Feature Requests

Open an issue with:
- Clear description of the feature
- Use case / motivation
- Possible implementation approach

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
