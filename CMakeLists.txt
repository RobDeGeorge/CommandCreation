cmake_minimum_required(VERSION 3.21)
project(mtgdeck LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 6.5 is the real floor, for MultiEffect (qml/PixelButton.qml and the two card
# shadows in Main.qml). Anything newer is fine.
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick Sql Network)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(mtgdeck
    src/main.cpp
    src/Db.h         src/Db.cpp
    src/DeckRules.h  src/DeckRules.cpp
    src/DeckIo.h     src/DeckIo.cpp
    src/CardModel.h  src/CardModel.cpp
    src/DeckModel.h  src/DeckModel.cpp
)

# qml/ is read where it sits; nothing is copied or duplicated into the build.
#
# QT_RESOURCE_ALIAS strips the leading "qml/" from every path. Without it the
# files would sit at .../MtgDeck/qml/Main.qml, and Main.qml's own references
# are written relative to itself ("assets/mtg-btn-copy-up.png", sibling
# components by bare name) — the alias is what keeps those resolving unchanged
# whether the file is read off disk or out of the binary.
file(GLOB_RECURSE MTG_QML CONFIGURE_DEPENDS
     RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "qml/*.qml" "qml/*.js")
file(GLOB_RECURSE MTG_ASSETS CONFIGURE_DEPENDS
     RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "qml/assets/*.png" "qml/assets/*.ttf")

foreach(f IN LISTS MTG_QML MTG_ASSETS)
    string(REGEX REPLACE "^qml/" "" alias "${f}")
    set_source_files_properties("${f}" PROPERTIES QT_RESOURCE_ALIAS "${alias}")
endforeach()

# The module URI must not differ from the executable name by case alone: they
# land side by side in the build directory, and a case-insensitive filesystem or
# sync client cannot tell "mtgdeck" from "MtgDeck". "CommandCreation" satisfies
# that — this is why the URI is not "MtgDeck", and the reason an in-tree build/
# is safe even inside Dropbox. Renaming either one puts that back at risk.
qt_add_qml_module(mtgdeck
    URI CommandCreation
    VERSION 1.0
    QML_FILES ${MTG_QML}
    RESOURCES ${MTG_ASSETS}
)

target_link_libraries(mtgdeck PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Sql Qt6::Network)

# Where a build run from this tree looks for data/cards.db and data/decks.db:
# against the sources rather than the working directory, so the app finds them
# however it is launched. It is the last of the three cases in Db.cpp's
# dataDir() — an installed copy prefers data/ beside the binary, and the
# WebAssembly build ignores this entirely for its preloaded path.
target_compile_definitions(mtgdeck PRIVATE
    MTG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")

# A copy somebody else can run:
#
#   cmake --install build --prefix dist
#
# lays down dist/bin/mtgdeck beside dist/bin/data/cards.db, which is the layout
# dataDir() checks first — so the installed copy reads its own database instead
# of the source tree it happened to be built in.
#
# cards.db only. decks.db holds whoever-built-this's own lists, and shipping it
# would hand them to everyone who downloads the app; SQLite's ATTACH creates the
# file on first run, and ensureDeckTables() fills in the schema.
install(TARGETS mtgdeck RUNTIME DESTINATION bin)
install(FILES data/cards.db DESTINATION bin/data OPTIONAL)

# The browser has no filesystem to install into. cards.db is packaged into
# Emscripten's virtual one at /data instead, which is the first case dataDir()
# answers with. Configure this build with:
#
#   ~/Qt/<ver>/wasm_singlethread/bin/qt-cmake -S . -B build-wasm \
#       -DQT_HOST_PATH=~/Qt/<ver>/gcc_64
#
# after sourcing emsdk_env.sh. The host path is not optional and its Qt version
# must equal the wasm kit's exactly.
#
# The 29 MB becomes a .data file the page downloads before the app starts, so
# this is the single biggest thing standing between a visitor and a first
# paint. decks.db is deliberately not preloaded: ATTACH creates it on first
# run, and it lives only in memory until Db::flush() pushes it to IndexedDB.
#
# decks.db is not preloaded and not packaged. It is mounted from IndexedDB at
# /decks by wasm/pre.js, which is injected here rather than by editing the
# generated mtgdeck.html — that file is rewritten on every build. -lidbfs.js is
# what puts the IDBFS backend in the binary; without it the mount fails at
# runtime and every deck is lost on reload, silently.
if(EMSCRIPTEN)
    set(MTG_PRE_JS "${CMAKE_CURRENT_SOURCE_DIR}/wasm/pre.js")
    target_link_options(mtgdeck PRIVATE
        "SHELL:--preload-file ${CMAKE_CURRENT_SOURCE_DIR}/data/cards.db@/data/cards.db"
        "SHELL:--pre-js ${MTG_PRE_JS}"
        -lidbfs.js)
    # --pre-js is not a dependency CMake infers, so an edit to pre.js alone
    # would otherwise not relink.
    set_target_properties(mtgdeck PROPERTIES LINK_DEPENDS "${MTG_PRE_JS}")
endif()
