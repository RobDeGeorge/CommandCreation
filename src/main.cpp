// MTG Commander deck builder — launch the UI.
//
// The QML it loads lives in qml/; see CMakeLists.txt for how it gets into the
// binary, and MTG_QML_DIR below for reading it off disk instead.
//
// (First run: python3 scripts/ingest.py to build the card database.)

#include "CardModel.h"
#include "Db.h"
#include "DeckModel.h"

#include <QDir>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QSslSocket>
#include <QUrl>

#include <cstdio>

namespace {

// ---- the UI font -----------------------------------------------------------
// This is the one place the typeface is chosen. Override without editing:
//
//   MTG_FONT=system ./mtgdeck               the platform's own font
//   MTG_FONT=/path/to/Other.ttf ./mtgdeck   any other font file
//   MTG_FONT_SIZE=20 ./mtgdeck              bigger
//
// The relative type scale (small / body / title) lives in qml/Retro.js.
const char *kDefaultFont = ":/qt/qml/CommandCreation/assets/PressStart2P-Regular.ttf";
constexpr int kDefaultFontSize = 8;

// Make the bitmap face the application default.
//
// Setting it on the QGuiApplication rather than per-control means menus,
// tooltips, dialog titles and every other bit of chrome Qt draws for us pick it
// up too — there is no second place to keep in sync.
//
// The face is drawn on an 8-row em, so one bitmap pixel is exactly
// pixelSize/8 screen pixels: sizes that are multiples of 8 land on whole pixels
// and anything else renders unevenly. Hinting is off for the same reason — the
// outlines are already on the pixel grid, and a hinter would only push them off
// it.
//
// Press Start 2P is monospaced at one em per glyph, which is why the sizes in
// qml/Retro.js are two steps smaller than the face it replaced: the same label
// is a third wider here at equal size. It carries ASCII and Latin-1 and nothing
// else — a ✓ or a ⚠ in a string comes out in whatever face Qt falls back to,
// which next to the bitmap glyphs reads as a mistake, so marks like those are
// drawn from the icon sprites instead.
void usePixelFont(QGuiApplication *app)
{
    const QByteArray choice = qEnvironmentVariable("MTG_FONT", QString::fromLatin1(kDefaultFont))
                                  .toUtf8();
    const int size = qEnvironmentVariableIntValue("MTG_FONT_SIZE") > 0
        ? qEnvironmentVariableIntValue("MTG_FONT_SIZE")
        : kDefaultFontSize;
    if (choice == "system")
        return;

    const int fontId = QFontDatabase::addApplicationFont(QString::fromUtf8(choice));
    const QStringList families = QFontDatabase::applicationFontFamilies(fontId);
    if (families.isEmpty()) {
        std::fprintf(stderr, "could not load font '%s' — using the system font\n",
                     choice.constData());
        return;
    }

    QFont font(families.first());
    font.setPixelSize(size);
    font.setHintingPreference(QFont::PreferNoHinting);
    app->setFont(font);
}

// Where Main.qml is read from. Out of the binary by default, which is what the
// WebAssembly build will need; MTG_QML_DIR points it at a directory instead, so
// the QML can be edited and reloaded without a rebuild.
QUrl mainQml()
{
    const QString override = qEnvironmentVariable("MTG_QML_DIR");
    if (!override.isEmpty())
        return QUrl::fromLocalFile(QDir(override).filePath(QStringLiteral("Main.qml")));
    return QUrl(QStringLiteral("qrc:/qt/qml/CommandCreation/Main.qml"));
}

} // namespace

int main(int argc, char *argv[])
{
    // No platform theme, and it has to be off before QGuiApplication is built.
    //
    // A desktop theme plugin (qt6ct here, gtk3 elsewhere) hands Qt Quick
    // Controls its own "system font", and that beats the face usePixelFont()
    // sets for everything derived from Control — every Label, ComboBox and
    // CheckBox — while plain Text still gets ours. The result is half the UI in
    // the bitmap face and half in the desktop's sans, which is not a look
    // anyone chose. This app draws all its own chrome and opens no native
    // dialogs, so there is nothing a platform theme can offer it.
    qunsetenv("QT_QPA_PLATFORMTHEME");

    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("MTG Commander Deck Builder"));
    usePixelFont(&app);

    // Say out loud when this build cannot open an https connection.
    //
    // Every card image is fetched from Scryfall's CDN over TLS, and Qt reaches
    // TLS through an OpenSSL it loads at runtime. When that library is not
    // there — the standing hazard on Android, where nothing ships one; see
    // CMakeLists.txt — nothing throws and nothing logs. Every request simply
    // fails, and the app is left looking like one whose image URLs are wrong.
    //
    // The failure it names is worth an hour of anyone's afternoon, and asking
    // costs one call at startup. On a phone this comes out in logcat, which is
    // the only place there is to say anything at all:
    //
    //     adb logcat -s mtgdeck:*
    if (!QSslSocket::supportsSsl()) {
        // The runtime string is what Qt actually managed to load, so it is
        // empty in the case being reported — printed anyway, because the one
        // thing worse than "nothing" here is a wrong version quietly loaded.
        std::fprintf(stderr,
                     "No TLS: Qt could not load OpenSSL, so every https request "
                     "will fail and no card image can load.\n"
                     "  built against: %s\n"
                     "  loaded:        %s\n",
                     qPrintable(QSslSocket::sslLibraryBuildVersionString()),
                     QSslSocket::sslLibraryVersionString().isEmpty()
                         ? "nothing"
                         : qPrintable(QSslSocket::sslLibraryVersionString()));
    }

    // One connection for both models, so a card added to a list is visible to
    // every query immediately rather than after a commit lands on disk.
    Db db;
    QString error;
    if (!db.open(&error)) {
        std::fprintf(stderr, "%s\n", qPrintable(error));
        return 1;
    }

    CardModel model(&db);
    DeckStore decks(&db);

    QQmlApplicationEngine engine;

    // Say why the UI didn't come up. Without this a stray brace in qml/ exits
    // 1 in silence — no file, no line, nothing to distinguish a typo from a
    // crash — while the db.open() failure above prints. Editing QML off disk
    // (MTG_QML_DIR) is the normal way to work on this app, so a bad edit is
    // the failure to expect, and the one worth naming.
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                     [](const QList<QQmlError> &warnings) {
                         for (const QQmlError &warning : warnings)
                             std::fprintf(stderr, "%s\n", qPrintable(warning.toString()));
                     });

    engine.rootContext()->setContextProperty(QStringLiteral("cardModel"), &model);
    engine.rootContext()->setContextProperty(QStringLiteral("deckStore"), &decks);
    engine.load(mainQml());
    if (engine.rootObjects().isEmpty()) {
        std::fprintf(stderr, "Couldn't load %s\n", qPrintable(mainQml().toString()));
        return 1;
    }

    return app.exec();
}
