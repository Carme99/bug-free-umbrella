# 🌂 Wiki Setup Guide

This document explains the Bug-Free Umbrella wiki structure and how to deploy it.

---

## 📚 What's Been Created

The wiki contains **10 comprehensive pages** totaling over **140KB of documentation**:

### Core Pages
1. **Home.md** - Wiki landing page with overview and navigation
2. **_Sidebar.md** - Sidebar navigation for easy browsing
3. **Getting-Started.md** - Comprehensive quick start guide

### Documentation Pages (Migrated from docs/)
4. **Script-Catalog.md** - Complete index of all 260+ scripts (from docs/NAVIGATION.md, now deleted)
5. **Script-Examples.md** - Detailed usage examples (from docs/SCRIPT-EXAMPLES.md, now deleted)
6. **Workflows.md** - Step-by-step workflow guides (from docs/WORKFLOWS.md, now deleted)
7. **Troubleshooting.md** - Common issues and solutions (from docs/TROUBLESHOOTING.md, now deleted)
8. **Intune-Sync-Guide.md** - Intune sync guide (from docs/INTUNE-SYNC-README.md, now deleted)

### Additional Pages (To Be Created)
- FAQ.md - Frequently asked questions
- Common-Use-Cases.md - Find scripts by task
- Release-Notes.md - Version history
- And 20+ category pages for each script type

---

## 🚀 How to Deploy the Wiki

GitHub wikis are separate Git repositories. Here's how to deploy:

### Step 1: Initialize the Wiki on GitHub

1. Go to https://github.com/Carme99/bug-free-umbrella
2. Click the "Wiki" tab
3. Click "Create the first page"
4. Add any content (we'll replace it)
5. Click "Save Page"

### Step 2: Clone the Wiki Repository

```bash
# Clone the wiki repo (separate from main repo)
git clone https://github.com/Carme99/bug-free-umbrella.wiki.git

cd bug-free-umbrella.wiki
```

### Step 3: Copy Wiki Files

```bash
# From your main repository, copy all wiki files
cp -r /path/to/bug-free-umbrella/wiki/* .

# Check what was copied
ls -la
```

### Step 4: Commit and Push to Wiki

```bash
# Add all wiki files
git add .

# Commit with descriptive message
git commit -m "Initial wiki setup with comprehensive documentation

- Wiki Home with navigation and quick start
- Sidebar navigation for easy browsing
- Getting Started guide for new users
- Complete Script Catalog (260+ scripts)
- Migrated all documentation from docs/ folder
- Script Examples, Workflows, Troubleshooting guides
- Intune Sync Guide

Total: 10 pages, 140KB+ of documentation"

# Push to wiki
git push origin master
```

### Step 5: Verify

Visit https://github.com/Carme99/bug-free-umbrella/wiki to see your wiki!

---

## 📁 Wiki File Structure

```
wiki/
├── Home.md                    # Landing page
├── _Sidebar.md                # Navigation sidebar
├── Getting-Started.md         # Quick start guide
├── Script-Catalog.md          # All 260+ scripts indexed
├── Script-Examples.md         # Usage examples
├── Workflows.md               # Step-by-step guides
├── Troubleshooting.md         # Common issues
├── Intune-Sync-Guide.md       # Intune sync guide
├── WIKI-SETUP.md             # This file
└── (more pages to be added)
```

---

## 🎯 What Changes Were Made to the Main Repo

### Files Modified

1. **README.md**
   - Added prominent wiki callout at top
   - Reorganized Quick Links section
   - Marked docs/ files as "legacy"

2. **docs/README.md**
   - Completely rewritten to point to wiki
   - Lists legacy files and wiki equivalents
   - Explains why wiki is better

### Files Created (Phase 1: Wiki Migration)

3. **wiki/** directory
   - All wiki content pages
   - Ready to be pushed to wiki repository

### Files Created (Phase 2: Community & Automation)

4. **CODE_OF_CONDUCT.md** - Community standards and behavior expectations
5. **SUPPORT.md** - Support channels, response times, how to get help
6. **GOVERNANCE.md** - Project governance, solo maintainer model, decision-making
7. **.github/CODEOWNERS** - Code ownership for PR reviews
8. **.editorconfig** - Editor formatting standards (PowerShell, Markdown, YAML)
9. **.github/workflows/stale.yml** - Auto-closes stale issues/PRs (60+ days)
10. **.github/workflows/link-checker.yml** - Validates all markdown links weekly
11. **.github/workflows/issue-labeler.yml** - Auto-labels new issues with 46 technology categories
12. **.github/scripts/create-labels.ps1** - Creates 46 GitHub labels in repository

### Files Deleted (Migrated to Wiki)
- docs/NAVIGATION.md (DELETED - migrated to Script-Catalog.md)
- docs/SCRIPT-EXAMPLES.md (DELETED - migrated to Script-Examples.md)
- docs/WORKFLOWS.md (DELETED - migrated to Workflows.md)
- docs/TROUBLESHOOTING.md (DELETED - migrated to Troubleshooting.md)
- docs/INTUNE-SYNC-README.md (DELETED - migrated to Intune-Sync-Guide.md)

---

## ✨ Benefits of the Wiki

### For Users
✅ **Better Search** - GitHub's built-in wiki search
✅ **Easier Navigation** - Sidebar and cross-links
✅ **More Organized** - Categorized content
✅ **Always Up-to-Date** - Single source of truth

### For Maintainers
✅ **Separate from Code** - Cleaner repo structure
✅ **Version Controlled** - Full Git history
✅ **Community Friendly** - Easy for contributors
✅ **More Flexible** - Better formatting options

### For the Project
✅ **Professional** - Polished documentation
✅ **Scalable** - Can grow indefinitely
✅ **Discoverable** - GitHub indexes wiki content
✅ **Accessible** - Clean URLs and permalinks

---

## 📖 Wiki Page Template

When creating new wiki pages, use this structure:

```markdown
# Page Title

Brief description of what this page covers.

---

## Table of Contents (for long pages)

1. [Section 1](#section-1)
2. [Section 2](#section-2)

---

## Content

Your content here...

---

## See Also

- [Related Page 1](Home) (example link)
- [Related Page 2](Script-Catalog) (example link)

---

**Last Updated:** YYYY-MM-DD
**Corresponds to:** vX.X.X
```

---

## 🗺️ Wiki Roadmap

### Phase 1: Core Documentation ✅ COMPLETE
- [x] Home page
- [x] Sidebar navigation
- [x] Getting Started
- [x] Script Catalog
- [x] Migrate existing docs

### Phase 2: Category Pages (To Do)
- [ ] Microsoft 365 & Intune page
- [ ] Server Management page
- [ ] DevOps & CI/CD page
- [ ] Cloud Infrastructure page
- [ ] Security & Compliance page
- [ ] Proactive Remediations page
- [ ] 14 more category pages

### Phase 3: Enhanced Content (To Do)
- [ ] FAQ page
- [ ] Common Use Cases page
- [ ] Release Notes pages (per version)
- [ ] Best Practices guide
- [ ] Architecture documentation
- [ ] Custom Development guide

### Phase 4: Script Pages (Future)
- [ ] Individual pages for major scripts
- [ ] Detailed parameter documentation
- [ ] Advanced usage scenarios
- [ ] Real-world examples

---

## 🔧 Maintenance

### Updating the Wiki

```bash
# Navigate to wiki repo
cd bug-free-umbrella.wiki

# Pull latest changes
git pull

# Edit files as needed
vim Page-Name.md

# Commit and push
git add .
git commit -m "Update: Description of changes"
git push
```

### Keeping Wiki in Sync with Code Repo

The wiki/ folder in the main repo serves as:
1. **Staging area** for wiki content
2. **Backup** of wiki pages
3. **Version control** alongside code releases

When updating wiki:
1. Edit in main repo's wiki/ folder
2. Test locally
3. Commit to main repo
4. Copy to wiki repo
5. Push to wiki

---

## 📊 Statistics

**Wiki Content:**
- **Total Pages:** 10 (with 30+ planned)
- **Total Size:** 140KB+ of documentation
- **Total Lines:** 4,500+ lines migrated
- **Scripts Documented:** 260+
- **Categories:** 20

**Coverage:**
- ✅ Getting Started - Complete
- ✅ Script Catalog - Complete (all 260+ scripts)
- ✅ Examples - Complete (migrated from docs/)
- ✅ Workflows - Complete (migrated from docs/)
- ✅ Troubleshooting - Complete (migrated from docs/)
- 🔄 Category Pages - In Progress
- 🔄 FAQ - Planned
- 🔄 Advanced Topics - Planned

---

## 🤝 Contributing to the Wiki

Contributors can edit the wiki directly through GitHub:

1. Visit any wiki page
2. Click "Edit" button (top right)
3. Make changes in the editor
4. Add commit message
5. Click "Save Page"

No pull request needed! (But changes are tracked in Git history)

---

## 🔗 Useful Links

**Wiki:**
- [Wiki Home](https://github.com/Carme99/bug-free-umbrella/wiki)
- [Wiki Repository](https://github.com/Carme99/bug-free-umbrella.wiki)

**Main Repository:**
- [Main Repo](https://github.com/Carme99/bug-free-umbrella)
- [Latest Release](https://github.com/Carme99/bug-free-umbrella/releases/latest)
- [Changelog](https://github.com/Carme99/bug-free-umbrella/blob/main/CHANGELOG.md)

---

**Created:** 2025-12-29
**Last Updated:** 2026-03-03
**Wiki Version:** 1.3.0
**Corresponds to:** v4.0.0 "Hurricane" 🌪️
**Created by:** [Claude Code](https://github.com/anthropics/claude-code)
