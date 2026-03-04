# MO2 v2.5.2 Backport Build Guide

This branch (`mo2-2.5.2-compat`) builds the **latest fomod-plus** against
MO2 v2.5.2's `uibase.dll` so the plugin can run on MO2 2.5.2 installations.

No source code (`.cpp`, `.h`) is modified — **only build configuration files
are changed**.

## Architecture

### Why not just use mob directly?

MO2 v2.5.2 was released on **2024-07-20**. At that time, the `uibase`,
`archive`, and `cmake_common` repositories used `master` as their release
branch. Since then, these repos have moved to v2.5.3+/v2.6.0 APIs:

| Repo | v2.5.2-era commit | API change |
|------|-------------------|------------|
| `cmake_common` | `8abcb29` (2024-07-01) | `mo2_configure_uibase()` removed in master |
| `uibase` | `e402d43` (2024-07-14) | Switched from `include()` to `find_package(mo2-cmake)` |
| `archive` | `a13e224` (2024-06-09) | Same API migration |

mob's `modorganizer::do_fetch()` ignores the `no_pull` setting and always
checks remote branches, falling back to `master`. This means mob will always
pull the **incompatible current master** for these repos.

### Solution

1. **Pre-clone** the 3 repos at their v2.5.2-era commits
2. **Disable** them in `mob.ini.2.5.2` so mob only builds third-party deps
3. **Build manually** via CMake using the same variables mob would pass
4. **Configure plugin** with `DEPENDENCIES_DIR` pointing to the pre-cloned
   `modorganizer_super/` to activate the v2.5.2 cmake code path

### Files changed from upstream

| File | Purpose |
|------|---------|
| `CMakePresets.json` | `compat-v2.5.2` preset |
| `build.ps1` | Build directory mapping for compat preset |
| `vcpkg.json` | Remove mo2-uibase/archive (built via mob) |
| `CMakeLists.txt` | Auto-discover DEPENDENCIES_DIR, Qt6 linking, patchfinder disabled |
| `installer/CMakeLists.txt` | Explicit Qt6 linking, PDB MSVC guard, Korean lrelease target |
| `scanner/CMakeLists.txt` | Explicit Qt6 linking, PDB MSVC guard, Korean lrelease target |
| `patchfinder/CMakeLists.txt` | uibase include dirs, Qt6 linking |
| `installer/FomodPlusInstaller.cpp` | QTranslator loading in init() for l10n |
| `installer/FomodPlusInstaller.h` | localizedName() override, description() tr() wrap |
| `scanner/FomodPlusScanner.cpp` | QTranslator loading in init() for l10n |
| `installer/fomod_plus_installer_ko.ts` | Korean translation source (NEW) |
| `scanner/fomod_plus_scanner_ko.ts` | Korean translation source (NEW) |
| `.github/workflows/build-2.5.2.yml` | Full CI workflow (NEW) |
| `.github/workflows/build.yml` | PR trigger restricted to main |
| `mob.ini.2.5.2` | mob config with core tasks disabled (NEW) |

## Merging Upstream Updates

```bash
# 1. Fetch upstream
git fetch upstream

# 2. Merge upstream/main into this branch
git merge upstream/main

# 3. Resolve conflicts (if any)
#    Most likely conflicts: CMakeLists.txt, vcpkg.json
#    Keep OUR changes for v2.5.2-specific sections
#    Accept THEIRS for source code and new features

# 4. Test the build
git push origin mo2-2.5.2-compat
# Wait for GitHub Actions to pass
```

### Conflict resolution tips

- **`CMakeLists.txt`**: Keep the `DEPENDENCIES_DIR` auto-discovery block
  (lines ~42-53) and the patchfinder disable. Accept upstream changes to
  everything else.
- **`vcpkg.json`**: Keep `mo2-cmake` only, do NOT re-add `mo2-uibase` or
  `mo2-archive`.
- **`installer/` and `scanner/` CMakeLists**: Keep the explicit `Qt6::Core
  Qt6::Gui Qt6::Widgets` in `target_link_libraries` and the `if(MSVC)` PDB
  guard.
- **Source files** (`.cpp`, `.h`): Accept upstream for everything EXCEPT
  the QTranslator loading blocks in `FomodPlusInstaller::init()` and
  `FomodPlusScanner::init()`. These are clearly marked with comments
  (`// Load plugin translations`). Also keep the `localizedName()` override
  and `tr()` wrap on `description()` in `FomodPlusInstaller.h`.
- **`.ts` files**: Upstream will never have Korean `.ts` files, so these
  will not conflict. If upstream adds new `tr()` strings, update the
  Korean `.ts` files to include translations for them.

## Troubleshooting

### `Unknown CMake command "mo2_configure_uibase"`
`cmake_common` was cloned from master instead of v2.5.2-era commit.
Check that `cmake_common` is disabled in `mob.ini.2.5.2` and pre-cloned at
`8abcb29`.

### `Could not find "mo2-uibase"`
`DEPENDENCIES_DIR` was not passed to the plugin configure step, or the
pre-cloned `uibase` was overwritten by mob. Ensure uibase is disabled in
`mob.ini.2.5.2`.

### `BOOST_ROOT is not defined`
The plugin configure step needs `BOOST_ROOT`, `QT_ROOT`, `PYTHON_ROOT`,
`CMAKE_INSTALL_PREFIX` passed explicitly when using the v2.5.2 cmake path.
