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
#
# Not on Android, where there is no such thing as a directory to install into
# and the target is not an executable at all — androiddeployqt packages the
# library into an .apk, and cards.db travels with it as an asset (below).
if(NOT ANDROID)
    install(TARGETS mtgdeck RUNTIME DESTINATION bin)
    install(FILES data/cards.db DESTINATION bin/data OPTIONAL)
endif()

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
    set(MTG_CARDS_DB "${CMAKE_CURRENT_SOURCE_DIR}/data/cards.db")
    target_link_options(mtgdeck PRIVATE
        "SHELL:--preload-file ${MTG_CARDS_DB}@/data/cards.db"
        "SHELL:--pre-js ${MTG_PRE_JS}"
        -lidbfs.js)

    # Both of these are consumed at link time by emcc, and CMake infers neither
    # as a dependency: without them a rebuild after re-running ingest.py, or
    # after editing pre.js, relinks nothing and silently keeps serving the
    # previous mtgdeck.data. That failure is quiet and convincing — the app
    # comes up, the cards are all there, and only something small is missing.
    set_target_properties(mtgdeck PROPERTIES
        LINK_DEPENDS "${MTG_PRE_JS};${MTG_CARDS_DB}")
endif()

# A phone has no filesystem to install into either, and no source tree to fall
# back on. cards.db rides inside the .apk as an Android asset and is unpacked to
# the app's private directory on first run — see unpackCards() in src/Db.cpp for
# why it cannot simply be read where it lands.
#
# Configure this build with scripts/build-android.sh, which is mostly a wrapper
# around the four paths androiddeployqt needs.
#
# Qt 6.8 is the floor here rather than the 6.5 above: the QT_ANDROID_* target
# properties below are what name the package and set its SDK levels, and an
# older Qt ignores them silently — leaving an app called "mtgdeck" under
# org.qtproject.example, which is a package name that cannot be published.
if(ANDROID)
    if(Qt6_VERSION VERSION_LESS 6.8)
        message(WARNING
            "Qt ${Qt6_VERSION} for Android: the QT_ANDROID_* properties below "
            "arrived in 6.8 and older versions ignore them, so this will build "
            "as org.qtproject.example.mtgdeck. Upgrade the Android kit.")
    endif()

    # Everything under this directory is merged into the package by
    # androiddeployqt, so assets/ here is what "assets:/" reads at runtime.
    # It is generated into the build tree rather than kept in the source tree,
    # because the only thing in it is a 17 MB database that git does not track.
    set(MTG_ANDROID_PACKAGE "${CMAKE_CURRENT_BINARY_DIR}/android-package")
    set(MTG_CARDS_DB "${CMAKE_CURRENT_SOURCE_DIR}/data/cards.db")
    if(NOT EXISTS "${MTG_CARDS_DB}")
        message(FATAL_ERROR
            "data/cards.db is missing, and on Android it has to be packaged at "
            "build time — there is nowhere for the app to find it later. "
            "Build it first: python3 scripts/ingest.py")
    endif()

    # POST_BUILD rather than configure time: androiddeployqt runs after the
    # library is linked, and copy_if_different means re-running ingest.py is
    # picked up by the next build without anyone having to remember it.
    add_custom_command(TARGET mtgdeck POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${MTG_CARDS_DB}" "${MTG_ANDROID_PACKAGE}/assets/data/cards.db"
        COMMENT "Packaging cards.db into the Android assets")

    set_target_properties(mtgdeck PROPERTIES
        QT_ANDROID_PACKAGE_SOURCE_DIR "${MTG_ANDROID_PACKAGE}"
        QT_ANDROID_APP_NAME "Command Creation"
        QT_ANDROID_PACKAGE_NAME "com.commandcreation.builder"
        QT_ANDROID_VERSION_NAME "0.1"
        QT_ANDROID_VERSION_CODE 1
        # 23 is the floor Qt 6 itself sets. 36 is a target, not a requirement:
        # it only says which behaviour changes the app opts into, and it is
        # separate again from the SDK the package is *compiled* against —
        # androiddeployqt takes that from the newest platform installed, so an
        # SDK without platforms;android-36 fails in Gradle on the AndroidX
        # dependency rather than here.
        QT_ANDROID_MIN_SDK_VERSION 23
        QT_ANDROID_TARGET_SDK_VERSION 36)

    # Without this the card images never load and the app looks broken rather
    # than offline — every picture comes from Scryfall's CDN. Guarded because
    # the command is 6.8-and-later; on an older kit, add the <uses-permission>
    # line to the manifest by hand (see the README).
    if(COMMAND qt_add_android_permission)
        qt_add_android_permission(mtgdeck NAME android.permission.INTERNET)
    endif()
endif()
