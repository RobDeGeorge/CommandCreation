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
# sync client cannot tell "mtgdeck" from "MtgDeck".
qt_add_qml_module(mtgdeck
    URI CommandCreation
    VERSION 1.0
    QML_FILES ${MTG_QML}
    RESOURCES ${MTG_ASSETS}
)

target_link_libraries(mtgdeck PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Sql Qt6::Network)

# data/cards.db and data/decks.db are resolved against the source tree rather
# than the working directory, so the app finds them however it is launched. The
# WebAssembly build will have to replace this with a preloaded path; it is
# deliberately the single place that assumption lives.
target_compile_definitions(mtgdeck PRIVATE
    MTG_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
