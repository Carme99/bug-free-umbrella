# Project Governance

## Overview

Bug-Free Umbrella is a **hobby project** created and maintained by [@Carme99](https://github.com/Carme99) with the assistance of [Claude Code](https://github.com/anthropics/claude-code), Anthropic's official CLI for Claude AI.

This document explains how the project is managed, how decisions are made, and how you can contribute.

## Project Philosophy

This project exists to:

- 🎯 **Share useful PowerShell automation** with the IT community
- 📚 **Learn and experiment** with modern DevOps practices
- 🤖 **Showcase AI-assisted development** using Claude Code
- 🌱 **Help others** solve real-world IT challenges

**It is NOT:**
- A commercial product with SLAs or support guarantees
- A full-time maintained project with rapid responses
- A comprehensive solution for all IT automation needs

## Governance Model

### Solo Maintainer Model

This project uses a **solo maintainer model**, which means:

- **@Carme99** has final decision-making authority on all contributions
- All PRs and issues are reviewed and merged by @Carme99
- No formal voting or consensus process - this is intentional for a hobby project
- Development happens in spare time alongside a full-time job

### Claude Code Partnership

This project is developed **with Claude Code**, which means:

- Claude Code assists with code generation, reviews, and documentation
- All code is reviewed by @Carme99 before merging
- Claude Code helps maintain code quality and consistency
- The project serves as a real-world example of AI-assisted development

## Decision-Making Process

### How Decisions Are Made

1. **Issues & Feature Requests**: Reviewed when time permits, prioritized by:
   - Impact on existing users
   - Alignment with project goals
   - Complexity and time required
   - Personal interest and learning value

2. **Pull Requests**: Evaluated based on:
   - Code quality (passes PSScriptAnalyzer)
   - Alignment with project standards (see CONTRIBUTING.md)
   - Documentation completeness
   - Test coverage (preferred but not required)
   - Usefulness to the broader community

3. **Breaking Changes**: Considered carefully with:
   - Migration guides provided
   - Version bumps following semantic versioning
   - Advance notice in CHANGELOG

### Acceptance Criteria

Contributions are more likely to be accepted if they:

- ✅ Follow the PowerShell style guide (see CONTRIBUTING.md)
- ✅ Include comment-based help and examples
- ✅ Pass PSScriptAnalyzer validation
- ✅ Are well-documented with clear use cases
- ✅ Don't introduce breaking changes without discussion
- ✅ Solve real-world problems for IT professionals

## Project Roles

### Maintainer (@Carme99)

**Responsibilities:**
- Review and merge pull requests
- Triage and respond to issues
- Make final decisions on project direction
- Maintain code quality standards
- Update documentation
- Create releases

**Authority:**
- Full commit access to the repository
- Can accept or reject any contribution
- Determines project roadmap and priorities

### Contributors (Everyone Else!)

**How to Contribute:**
- Submit bug reports via GitHub Issues
- Propose features or enhancements
- Submit pull requests with improvements
- Improve documentation
- Help answer questions from other users
- Share the project with others who might benefit

**Recognition:**
- All contributors are acknowledged in release notes
- Significant contributors may be mentioned in README
- Community contributions are celebrated and appreciated! 🎉

### Special Recognition: Claude Code

Claude Code is an AI assistant that helps with:
- Generating boilerplate code
- Reviewing code for best practices
- Writing documentation
- Maintaining consistency across scripts
- Debugging and troubleshooting

While Claude Code assists significantly, all final decisions and reviews are done by @Carme99.

## Communication Channels

### Primary: GitHub Issues
- **Bug Reports**: Use the bug report template
- **Feature Requests**: Use the feature request template
- **Script Requests**: Use the script request template
- **Questions**: Open an issue with "question" label
- **Discussions**: Comment on existing issues

### Secondary: Pull Requests
- For code contributions
- For documentation improvements
- Include detailed descriptions of changes

### Private: GitHub Messages
- Code of Conduct violations
- Security vulnerabilities (see SECURITY.md)
- Private concerns about the project

## Release Process

### Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (v3.0.0): Breaking changes, major restructuring
- **MINOR** (v3.1.0): New features, script additions
- **PATCH** (v3.1.1): Bug fixes, documentation updates

### Release Cadence

There is **no fixed release schedule**. Releases happen when:

- Significant new features are ready
- Critical bugs are fixed
- Enough changes have accumulated
- @Carme99 has time to prepare a release

Typically expect releases every 1-3 months, but this varies.

### Release Process

1. Update CHANGELOG.md with all changes
2. Bump version in relevant files
3. Create a git tag (e.g., `v3.1.0`)
4. Push tag to GitHub
5. Create GitHub Release with notes
6. Announce in README if significant

## Conflict Resolution

### If You Disagree With a Decision

1. **Ask for clarification**: Comment on the issue/PR explaining your concerns
2. **Provide rationale**: Explain why you think a different approach is better
3. **Respect the final decision**: As a solo maintainer project, @Carme99 has final say
4. **Fork if needed**: Open source means you can fork and take a different direction!

### If You Experience Problematic Behavior

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for reporting process.

## Inactive Maintenance

If @Carme99 becomes unavailable or unable to maintain the project:

- The repository will remain available under Apache License 2.0
- Community members are encouraged to fork and continue development
- No formal succession plan exists (hobby project)
- Scripts remain useful as standalone tools even without active maintenance

## Changes to Governance

This governance document may be updated as the project evolves. Major changes will be:

- Announced in the CHANGELOG
- Explained in commit messages
- Open to community feedback via issues

## Questions About Governance?

Have questions about how the project is run? Open an issue or reach out via GitHub message.

---

## Summary: TL;DR

- 🧑‍💻 **Solo hobby project** maintained by @Carme99 with Claude Code
- 🤖 **AI-assisted development** showcasing modern tooling
- 🕐 **No guaranteed timelines** - best effort support when available
- 💡 **Community contributions welcome** - PRs and issues appreciated
- ✅ **Final decisions by @Carme99** - no formal voting or consensus
- 📝 **Semantic versioning** - breaking changes are clearly communicated
- 🚀 **Open source** (Apache 2.0) - fork freely if direction diverges

**Thanks for being part of this project!** Your understanding and patience make this hobby project sustainable and enjoyable. 🙏
