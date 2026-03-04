cmake_minimum_required(VERSION 3.30)
include(FetchContent)
add_library(fomod_plus_installer SHARED)
set_property(TARGET fomod_plus_installer PROPERTY CXX_STANDARD 20)

target_include_directories(
        fomod_plus_installer
        PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/../share
        ${MO2_UIBASE_INCLUDE_DIRS}
        ${MO2_ARCHIVE_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}
)

FetchContent_Declare(
        pugixml
        GIT_REPOSITORY https://github.com/zeux/pugixml
        GIT_TAG v1.14
        PATCH_COMMAND ${CMAKE_COMMAND}
                -DPUGIXML_CMAKELISTS=<SOURCE_DIR>/CMakeLists.txt
                -P ${CMAKE_CURRENT_LIST_DIR}/../cmake/patch_pugixml.cmake
)

file(GLOB SHARE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../share/**/*.cpp")
target_sources(fomod_plus_installer PRIVATE ${SHARE_SOURCES})

FetchContent_Declare(json URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz)
FetchContent_MakeAvailable(pugixml json)

set(project_type plugin)
project(fomod_plus_installer)

target_link_libraries(fomod_plus_installer PRIVATE mo2::uibase pugixml nlohmann_json::nlohmann_json dbghelp Qt6::Core Qt6::Gui Qt6::Widgets)
mo2_configure_plugin(fomod_plus_installer WARNINGS OFF PRIVATE_DEPENDS)

if(MSVC)
    # Ensure PDB is generated
    target_compile_options(fomod_plus_installer PRIVATE $<$<CONFIG:RelWithDebInfo>:/Zi>)
    target_link_options(fomod_plus_installer PRIVATE $<$<CONFIG:RelWithDebInfo>:/DEBUG>)

    # Install PDB alongside DLL
    install(FILES $<TARGET_PDB_FILE:fomod_plus_installer>
            DESTINATION ${CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO}
            CONFIGURATIONS RelWithDebInfo
            OPTIONAL)
endif()

mo2_install_target(fomod_plus_installer)

# Korean translation (.ts -> .qm)
set(_ko_ts "${CMAKE_CURRENT_SOURCE_DIR}/fomod_plus_installer_ko.ts")
set(_ko_qm "${CMAKE_CURRENT_BINARY_DIR}/fomod_plus_installer_ko.qm")
add_custom_command(OUTPUT ${_ko_qm}
    COMMAND ${QT_ROOT}/bin/lrelease ${_ko_ts} -qm ${_ko_qm}
    DEPENDS ${_ko_ts} VERBATIM)
add_custom_target(fomod_plus_installer_lrelease_ko DEPENDS ${_ko_qm})
add_dependencies(fomod_plus_installer fomod_plus_installer_lrelease_ko)
install(FILES ${_ko_qm} DESTINATION bin/translations)
