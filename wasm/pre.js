// Deck storage that outlives the tab.
//
// Injected ahead of Qt's generated module with --pre-js (see CMakeLists.txt)
// rather than by editing mtgdeck.html, which the build regenerates.
//
// Only decks.db needs any of this. cards.db is preloaded into the in-memory
// filesystem and is never written by the user, which is exactly why the two
// live in separate directories: this mount can cover the 28 KB that changes
// without going anywhere near the 29 MB that doesn't.

Module['preRun'] = Module['preRun'] || [];

// Read the saved decks back in.
//
// This has to finish before main() runs. If it didn't, Db::open() would ATTACH
// an empty file and the user would watch every deck they own fail to appear.
// FS.syncfs is asynchronous, so the load is registered as a run dependency:
// Emscripten holds main() until the matching removeRunDependency. That is the
// one hook that buys an async step before startup without turning on Asyncify,
// which would cost size and speed everywhere to solve it here.
Module['preRun'].push(function () {
    FS.mkdir('/decks');
    FS.mount(IDBFS, {}, '/decks');

    addRunDependency('mtg-decks-load');
    FS.syncfs(true, function (err) {
        // A first visit has nothing stored yet and reports no error; a real
        // failure here means starting with no decks, so say so rather than
        // letting it look like they were never saved.
        if (err) console.error('[mtgdeck] could not read saved decks:', err);
        removeRunDependency('mtg-decks-load');
    });
});

// Push /decks back out to IndexedDB. Db::flush() calls this after every change.
//
// Coalesced, not queued. A sync already in flight is not awaited — it just sets
// a flag that runs one more pass when it lands, so importing a hundred-card
// deck costs one write here instead of a hundred, and the last call always wins.
Module['mtgSyncDecks'] = (function () {
    var syncing = false;
    var pending = false;

    function run() {
        syncing = true;
        FS.syncfs(false, function (err) {
            syncing = false;
            if (err) console.error('[mtgdeck] could not save decks:', err);
            if (pending) {
                pending = false;
                run();
            }
        });
    }

    return function () {
        if (syncing) {
            pending = true;
            return;
        }
        run();
    };
})();
