#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstraps a standalone, zero-mob CMake Config-Package SDK for Mod Organizer v2.5.2.

.DESCRIPTION
    Materializes standards-compliant CMake config packages (mo2-cmake, mo2-uibase, mo2-archive)
    targeting the exact Mod Organizer v2.5.2 binary ABI without requiring the heavyweight
    classic `mob` umbrella build or compiling 16 transitive third-party dependencies:
      1. Downloads and SHA-256 verifies official `Mod.Organizer-2.5.2-uibase.7z` (uibase.lib + headers)
         and `Mod.Organizer-2.5.2-src.7z` (archive.h) from ModOrganizer2/modorganizer release v2.5.2.
      2. Synthesizes `archive.lib` directly from `archive.dll`'s exact MSVC x64 mangled export table
         via `lib.exe /def:archive.def /machine:x64`.
      3. Emits `mo2-cmakeConfig.cmake`, `mo2-uibaseConfig.cmake`, and `mo2-archiveConfig.cmake`
         compatible with upstream's Ninja + BuildProfile pipeline and hardened with
         `_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR` for MSVC 14.40+/14.50 STL runtime compatibility.
#>
param(
    [string]$SdkDir = "$PSScriptRoot/../build-mo2-2.5.2-sdk",
    [string]$CacheDir = "$PSScriptRoot/../build-mo2-2.5.2-sdk/.cache",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$UibaseUrl    = 'https://github.com/ModOrganizer2/modorganizer/releases/download/v2.5.2/Mod.Organizer-2.5.2-uibase.7z'
$UibaseSha256 = 'CF066A13556F004F558BFA69FAC61AA1ACE700280DB337259BFB6F1AAA1D5E5C'

$SrcUrl       = 'https://github.com/ModOrganizer2/modorganizer/releases/download/v2.5.2/Mod.Organizer-2.5.2-src.7z'
$SrcSha256    = '835E7B218CB7F7B6D5C89F37D5DD17384804FA6DC849FA5200FA1576B3EF1DC8'

function Resolve-NormalizedPath([string]$PathValue) {
    New-Item -ItemType Directory -Force -Path $PathValue | Out-Null
    return (Resolve-Path -LiteralPath $PathValue).Path
}

function Find-MsvcLibExe {
    $cmd = Get-Command lib.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $installPaths = & $vswhere -all -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        foreach ($vs in $installPaths) {
            $libCandidate = Get-ChildItem -Path "$vs\VC\Tools\MSVC" -Recurse -Filter 'lib.exe' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'Host[xX]64\\x64\\lib\.exe$' } |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($libCandidate) { return $libCandidate.FullName }
        }
    }
    throw 'Unable to locate MSVC x64 lib.exe. Install Visual Studio C++ x64 build tools.'
}

function Get-VerifiedArchive([string]$Url, [string]$ExpectedSha256, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        if ($actual -eq $ExpectedSha256) {
            return
        }
        Remove-Item -LiteralPath $Destination -Force
    }
    Write-Host "[MO2-2.5.2-SDK] Downloading $(Split-Path $Destination -Leaf)..."
    & curl.exe -fL --retry 3 $Url -o $Destination
    if ($LASTEXITCODE -ne 0) { throw "Failed to download $Url" }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256) {
        throw "SHA-256 mismatch for $Destination (expected $ExpectedSha256, got $actual)"
    }
}

$sdkRoot   = Resolve-NormalizedPath $SdkDir
$cacheRoot = Resolve-NormalizedPath $CacheDir
$stampFile = Join-Path $sdkRoot 'sdk-stamp.json'

if (!$Force -and (Test-Path -LiteralPath $stampFile -PathType Leaf) -and
    (Test-Path -LiteralPath "$sdkRoot/lib/uibase.lib" -PathType Leaf) -and
    (Test-Path -LiteralPath "$sdkRoot/lib/archive.lib" -PathType Leaf) -and
    (Test-Path -LiteralPath "$sdkRoot/lib/cmake/mo2-cmake/mo2-cmakeConfig.cmake" -PathType Leaf)) {
    $stamp = Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($stamp -and $stamp.schemaVersion -eq 2) {
        Write-Host "[MO2-2.5.2-SDK] Ready at $sdkRoot"
        return
    }
}

$uibaseArchive = Join-Path $cacheRoot 'Mod.Organizer-2.5.2-uibase.7z'
$srcArchive    = Join-Path $cacheRoot 'Mod.Organizer-2.5.2-src.7z'

Get-VerifiedArchive -Url $UibaseUrl -ExpectedSha256 $UibaseSha256 -Destination $uibaseArchive
Get-VerifiedArchive -Url $SrcUrl -ExpectedSha256 $SrcSha256 -Destination $srcArchive

$incUibase  = Resolve-NormalizedPath "$sdkRoot/include/uibase"
$incArchive = Resolve-NormalizedPath "$sdkRoot/include/archive"
$libDir     = Resolve-NormalizedPath "$sdkRoot/lib"
$cmakeUibase  = Resolve-NormalizedPath "$sdkRoot/lib/cmake/mo2-uibase"
$cmakeArchive = Resolve-NormalizedPath "$sdkRoot/lib/cmake/mo2-archive"
$cmakeMo2     = Resolve-NormalizedPath "$sdkRoot/lib/cmake/mo2-cmake"

$extractTemp = Join-Path $cacheRoot "extract-$([guid]::NewGuid())"
New-Item -ItemType Directory -Force -Path $extractTemp | Out-Null
try {
    & 7z x $uibaseArchive "-o$extractTemp/uibase" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '7z failed extracting uibase archive' }

    & 7z x $srcArchive "-o$extractTemp/src" 'archive/src/archive.h' -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '7z failed extracting archive.h from src archive' }

    Copy-Item -LiteralPath "$extractTemp/uibase/uibase.lib" -Destination "$libDir/uibase.lib" -Force
    Remove-Item -LiteralPath "$extractTemp/uibase/uibase.lib" -Force
    Copy-Item -Path "$extractTemp/uibase/*" -Destination $incUibase -Recurse -Force
    Copy-Item -LiteralPath "$extractTemp/src/archive/src/archive.h" -Destination "$incArchive/archive.h" -Force
} finally {
    if (Test-Path -LiteralPath $extractTemp) {
        Remove-Item -LiteralPath $extractTemp -Recurse -Force
    }
}

# Synthesize COFF import library for MO2 v2.5.2 archive.dll (exports single factory symbol CreateArchive).
$archiveDef = Join-Path $libDir 'archive.def'
@'
LIBRARY archive.dll
EXPORTS
    ?CreateArchive@@YA?AV?$unique_ptr@VArchive@@U?$default_delete@VArchive@@@std@@@std@@XZ
'@ | Set-Content -LiteralPath $archiveDef -Encoding ASCII

$libExe = Find-MsvcLibExe
& $libExe /nologo "/def:$archiveDef" "/out:$libDir/archive.lib" /machine:x64 | Out-Null
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath "$libDir/archive.lib" -PathType Leaf)) {
    throw 'MSVC lib.exe failed to synthesize archive.lib'
}

# Emit mo2-uibaseConfig.cmake
@'
include_guard(GLOBAL)
get_filename_component(_mo2_sdk_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

find_package(Qt6 COMPONENTS Core Gui Widgets Network REQUIRED)

if(NOT TARGET mo2::uibase)
    add_library(mo2-uibase SHARED IMPORTED GLOBAL)
    set_target_properties(mo2-uibase PROPERTIES
        IMPORTED_IMPLIB "${_mo2_sdk_root}/lib/uibase.lib"
        INTERFACE_INCLUDE_DIRECTORIES "${_mo2_sdk_root}/include;${_mo2_sdk_root}/include/uibase;${_mo2_sdk_root}/include/uibase/game_features"
        INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${_mo2_sdk_root}/include;${_mo2_sdk_root}/include/uibase;${_mo2_sdk_root}/include/uibase/game_features"
        INTERFACE_LINK_LIBRARIES "Qt6::Core;Qt6::Gui;Qt6::Widgets;Qt6::Network"
        INTERFACE_COMPILE_DEFINITIONS "_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR"
    )
    add_library(mo2::uibase ALIAS mo2-uibase)
endif()
'@ | Set-Content -LiteralPath "$cmakeUibase/mo2-uibaseConfig.cmake" -Encoding UTF8

# Emit mo2-archiveConfig.cmake
@'
include_guard(GLOBAL)
get_filename_component(_mo2_sdk_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

if(NOT TARGET mo2::archive)
    add_library(mo2-archive SHARED IMPORTED GLOBAL)
    set_target_properties(mo2-archive PROPERTIES
        IMPORTED_IMPLIB "${_mo2_sdk_root}/lib/archive.lib"
        INTERFACE_INCLUDE_DIRECTORIES "${_mo2_sdk_root}/include;${_mo2_sdk_root}/include/archive"
        INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${_mo2_sdk_root}/include;${_mo2_sdk_root}/include/archive"
    )
    add_library(mo2::archive ALIAS mo2-archive)
endif()
'@ | Set-Content -LiteralPath "$cmakeArchive/mo2-archiveConfig.cmake" -Encoding UTF8

# Emit mo2-cmakeConfig.cmake (implements MO2 v2.5.2 plugin/install/translation helpers cleanly without mob)
@'
include_guard(GLOBAL)
include(CMakeParseArguments)

define_property(TARGET PROPERTY MO2_TARGET_TYPE INHERITED
    BRIEF_DOCS "Target type for MO2 C++ target."
    FULL_DOCS "Automatically set when using mo2_configure_plugin.")

function(mo2_configure_plugin TARGET)
    cmake_parse_arguments(MO2 "SOURCE_TREE"
        "WARNINGS;EXTERNAL_WARNINGS;PERMISSIVE;BIGOBJ;CLI;TRANSLATIONS;AUTOMOC"
        "EXTRA_TRANSLATIONS;PUBLIC_DEPENDS;PRIVATE_DEPENDS"
        ${ARGN})

    if(NOT DEFINED MO2_TRANSLATIONS)
        set(MO2_TRANSLATIONS ON)
    endif()
    if(NOT DEFINED MO2_AUTOMOC)
        set(MO2_AUTOMOC ON)
    endif()

    find_package(Qt6 COMPONENTS Core Gui Widgets LinguistTools REQUIRED)

    if(MO2_AUTOMOC)
        set_target_properties(${TARGET} PROPERTIES AUTOMOC ON AUTOUIC ON AUTORCC ON)
    endif()

    set_target_properties(${TARGET} PROPERTIES
        CXX_STANDARD 20
        CXX_EXTENSIONS OFF
        MO2_TARGET_TYPE "plugin"
    )

    if(MSVC)
        target_compile_options(${TARGET} PRIVATE
            /MP
            /permissive-
            /utf-8
            /external:anglebrackets
            /external:W0
            $<$<CONFIG:RelWithDebInfo>:/O2 /Zi>
        )
        target_link_options(${TARGET} PRIVATE
            $<$<CONFIG:RelWithDebInfo>:/DEBUG /INCREMENTAL:NO /OPT:REF /OPT:ICF>
        )
    endif()

    file(GLOB_RECURSE _src_files CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.cpp")
    file(GLOB_RECURSE _hdr_files CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.h")
    file(GLOB_RECURSE _qrc_files CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.qrc")
    file(GLOB_RECURSE _rc_files  CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.rc")
    file(GLOB_RECURSE _ui_files  CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.ui")

    target_sources(${TARGET} PRIVATE
        ${_src_files}
        ${_hdr_files}
        ${_qrc_files}
        ${_rc_files}
        ${_ui_files}
    )

    execute_process(
        COMMAND git log -1 --format=%h
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        OUTPUT_VARIABLE _git_hash
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    target_compile_definitions(${TARGET} PRIVATE
        _UNICODE
        UNICODE
        NOMINMAX
        _CRT_SECURE_NO_WARNINGS
        BOOST_CONFIG_SUPPRESS_OUTDATED_MESSAGE
        _SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING
        _DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR
        QT_MESSAGELOGCONTEXT
        GITID="${_git_hash}"
    )

    target_link_libraries(${TARGET} PUBLIC mo2::uibase PRIVATE Version Dbghelp)

    foreach(_dep IN LISTS MO2_PUBLIC_DEPENDS)
        if(TARGET "mo2::${_dep}")
            target_link_libraries(${TARGET} PUBLIC "mo2::${_dep}")
        endif()
    endforeach()
    foreach(_dep IN LISTS MO2_PRIVATE_DEPENDS)
        if(TARGET "mo2::${_dep}")
            target_link_libraries(${TARGET} PRIVATE "mo2::${_dep}")
        endif()
    endforeach()

    if(MO2_TRANSLATIONS)
        set(_qm_files "")
        foreach(_lang IN ITEMS en ko)
            set(_ts_file "${CMAKE_CURRENT_SOURCE_DIR}/${TARGET}_${_lang}.ts")
            set(_qm_file "${CMAKE_CURRENT_BINARY_DIR}/${TARGET}_${_lang}.qm")
            if(EXISTS "${_ts_file}")
                add_custom_command(
                    OUTPUT "${_qm_file}"
                    COMMAND Qt6::lrelease "${_ts_file}" -qm "${_qm_file}"
                    DEPENDS "${_ts_file}"
                    VERBATIM
                )
                list(APPEND _qm_files "${_qm_file}")
            endif()
        endforeach()
        if(_qm_files)
            add_custom_target("${TARGET}_lrelease" DEPENDS ${_qm_files})
            add_dependencies(${TARGET} "${TARGET}_lrelease")
            set_property(TARGET ${TARGET} PROPERTY FOMOD_PLUS_TRANSLATIONS ${_qm_files})
            install(FILES ${_qm_files} DESTINATION bin/translations)
        endif()
    endif()
endfunction()

function(mo2_install_target TARGET)
    install(TARGETS ${TARGET}
        RUNTIME DESTINATION bin/plugins
        ARCHIVE DESTINATION libs
    )
    if(MSVC)
        install(FILES $<TARGET_PDB_FILE:${TARGET}> DESTINATION pdb OPTIONAL)
    endif()
endfunction()

function(mo2_install_plugin TARGET)
    mo2_install_target(${TARGET} ${ARGN})
endfunction()
'@ | Set-Content -LiteralPath "$cmakeMo2/mo2-cmakeConfig.cmake" -Encoding UTF8

@{
    schemaVersion = 2
    mo2Version    = '2.5.2'
    uibaseSha256  = $UibaseSha256
    srcSha256     = $SrcSha256
    generatedAt   = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $stampFile -Encoding UTF8

Write-Host "[MO2-2.5.2-SDK] Successfully bootstrapped MO2 v2.5.2 CMake SDK at $sdkRoot"
