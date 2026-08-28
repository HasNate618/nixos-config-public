import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "Data.js" as Data
import "EmojiData.js" as EmojiData
import "omni" as Omni
import "omni/Tiles.js" as Tiles

// Omni-menu palette. Fuses installed apps (.desktop scan) with every
// `omarchy-menu` action, scored against title, category, and per-entry
// synonyms (so "wallpaper" finds Background, "reboot" finds Restart).
// Drill-down rows pivot the list to a category, fd file search, gh repo
// search, processes, or themes. Toggle via:
//   qs -c desktop ipc call palette toggle
//
// Source layout: this file is the entry and keeps all state (search
// index, scoring, mode flags, IPC, shortcuts, the keyboard handler,
// and the panel chrome). Visual subtrees live alongside in `omni/`:
//   omni/SearchInput.qml     prompt glyph + query text + caret
//   omni/ResultList.qml      ListView + row delegate
//   omni/PreviewPane.qml     preview header + body for all modes
//   omni/Footer.qml          exec line for the selected item
//   omni/Format.js           markdown formatters (tldr, chat)
//   omni/Tiles.js            quick-tile static data + dyn builder
Item {
    id: root

    required property var theme
    // Navbar instance handed in from shell.qml. Used by Quick mode to
    // bind live telemetry (battery, audio, network, bluetooth, weather,
    // …) into the tile grid. Optional so OmniMenu can still load without
    // a navbar (e.g. headless config); Quick tiles fall back to "—" then.
    // Named `navbar` to avoid colliding with the existing `nav: []`
    // category-row array further down.
    property var navbar: null

    readonly property color paper:   theme.paper
    readonly property color ink:     theme.ink
    readonly property color inkDeep: theme.inkDeep
    readonly property color sumi:    theme.inkDeep
    readonly property color indigo:  theme.indigo
    readonly property color seal:    theme.seal
    readonly property color bg:      theme.bg
    readonly property color fg:      theme.fg
    readonly property color muted:   theme.muted
    readonly property color sep:     theme.sep
    readonly property color rowHi:   theme.rowHi
    readonly property color rowSel:  theme.rowSel

    // Scoring weights and result cap. omarchy-menu has ~125 entries plus the
    // 12 nav rows plus ~80-200 .desktop apps, so the cap lets a quick
    // page-down still reach near-matches without overdrawing.
    readonly property int scPrefix: 100
    readonly property int scTitle:  60
    readonly property int scKw:     20
    readonly property int scCat:    10
    readonly property int maxResults: 250

    readonly property string mono:  theme.mono
    readonly property string serif: theme.serif

    readonly property int cornerRadius: theme.cornerRadius

    // Sources that feed `allItems`. AppScan reads .desktop files;
    // NavbarApps probes the navbar shell for its IpcHandler widgets and
    // surfaces only the ones it actually exposes (so users on a
    // navbar-less setup see nothing instead of broken rows).
    AppScan { id: appScan }
    NavbarApps { id: navbarApps }
    readonly property alias appsLoaded: appScan.loaded

    // ---------- Visibility / state ----------
    // Trailing underscore avoids shadowing Item.visible — read by the
    // PanelWindow's visibility binding below.
    property bool visible_: false
    property bool _closeQueued: false
    property string query: ""
    property int selectedIndex: 0
    // When a keyboard nav event fires, suppress mouse-hover selection
    // updates briefly so arrow keys don't get hijacked by the cursor.
    property bool _mouseBlocked: false
    Timer {
        id: _mouseBlockTimer
        interval: 300
        onTriggered: root._mouseBlocked = false
    }
    function blockMouse() {
        root._mouseBlocked = true;
        _mouseBlockTimer.restart();
    }
    // Active drill-down. "" means root (category navigators + everything
    // searchable); any other value pins the list to that category. Set by
    // activating a category nav row; cleared by Esc / Backspace-on-empty.
    property string categoryFilter: ""

    // File and GitHub search drills reuse the category machinery: the
    // Files/GitHub nav rows set categoryFilter to one of Data's sentinels,
    // filteredItems pivots to the matching results array, and goUp/Esc
    // unwind via the same path as any other category.
    readonly property bool clipMode: root.categoryFilter === Data.clipCategory
    // Removed modes — stubbed out so dead code paths are skipped
    readonly property bool tldrMode: false
    readonly property bool llmMode: false
    readonly property bool fileMode: false
    readonly property bool ghMode: false
    readonly property bool favMode: false
    readonly property bool histMode: false
    readonly property bool procMode: false
    readonly property bool themeMode: false
    readonly property bool quickMode: false
    readonly property bool quickExpanded: false
    readonly property int  quickGridCols: 4
    property var tldrItems: []
    property var chatItems: []
    property var procItems: []
    property var themeItems: []
    property var fileItems: []
    property var ghItems: []
    property string tldrPreview: ""
    property bool ghReady: false
    readonly property bool emojiMode: root.categoryFilter === Data.emojiCategory
    // Quick mode swaps the result list for a live-tile grid. Tiles bind
    // to nav telemetry for instantaneous state; clicking one drops an
    // expanded detail panel below the grid with that tile's adjustments.
// Live font multiplier — every `font.pixelSize` binding in this
    // file multiplies its base by this value. Ctrl++ / Ctrl+- nudge
    // it in 0.1 steps; Ctrl+= resets to 1.0. Clamped to keep the
    // panel usable at extremes.
    property real fontScale: 1.4
    function bumpFontScale(delta) {
        const next = Math.max(0.7, Math.min(2.0, root.fontScale + delta));
        // Snap to one decimal so successive bumps don't drift on
        // floating-point round-off.
        root.fontScale = Math.round(next * 10) / 10;
    }
    // null = no expansion; otherwise the tile object whose detail panel
    // is currently revealed under the grid.
    property var expandedTile: null
    // Single source of truth for "in Quick mode with a tile open" — the
    // grid column count, the compressed-tile flag, and the side-panel
    // visibility all key off it.
    function expandTile(t) {
        if (!t) { root.expandedTile = null; return; }
        // Click same tile to collapse; click a different tile to swap.
        root.expandedTile = (root.expandedTile && root.expandedTile.key === t.key)
                            ? null : t;
    }
    function collapseTile() { root.expandedTile = null; }

    Bookmarks { id: bookmarks }

    // ---------- Quick tiles ----------
    // Split into a *static* base array (the Repeater's model) and a
    // *dynamic* dict of per-tile live data, indexed by tile.key. The
    // base never changes, so the Repeater's 12 delegates are built once
    // and never torn down — clicks and hover state survive across
    // navbar ticks. Dynamic fields (glyph/label/sub/tone) read out of
    // `quickTilesDyn` via the `tileDyn()` helper; when the dict swaps,
    // only the delegate's text/color bindings re-evaluate. Order
    // matches the Samsung-style quick panel — most glanced
    // (battery/audio/wifi/bt) first.
    readonly property var quickTilesBase: Tiles.base

    // Dynamic per-tile data — keyed by tile.key. Gated on `visible_`
    // so navbar ticks don't wake the rebuild while the palette is
    // closed (the previous snapshot keeps the Repeater happy when the
    // user re-opens, before this binding re-evaluates).
    property var _quickTilesDynCache: ({})
    readonly property var quickTilesDyn: {
        if (!root.visible_) return root._quickTilesDynCache;
        // No navbar yet (shell reload, hot-swap, or a tick before the
        // sibling Navbar wires up): return an empty snapshot but do NOT
        // store it, so the cached previous-good values survive the gap
        // and the close-fade never flashes blank tiles.
        if (!root.navbar) return ({});
        const dyn = Tiles.buildDyn(root.navbar);
        root._quickTilesDynCache = dyn;
        return dyn;
    }

    // Resolve the dynamic side of a base tile. Returns an empty object
    // (not undefined) so delegate bindings can chain `.glyph` / `.sub`
    // without an `?.` chain on every read.
    function tileDyn(t) { return (t && root.quickTilesDyn[t.key]) || ({}); }

    // No search field in quickMode — tiles are always the full set so
    // grid arithmetic (gridCols * row) stays predictable. Kept as a
    // separate property so non-quick code paths don't need to branch.
    readonly property var filteredQuickTiles: root.quickTilesBase

    // Same launch envelope as activate() so popup IPCs (qs ipc call …)
    // get fired off-process and quickshell can close immediately.
    function activateQuickTile(t) {
        if (!t || !t.action) return;
        runner.command = ["sh", "-c",
                          "setsid -f uwsm-app -- bash -c "
                          + JSON.stringify(t.action)
                          + " >/dev/null 2>&1"];
        runner.running = false;
        runner.running = true;
        root.close();
    }

    // Long-press / right-click hook. Stays open so a "refresh weather"
    // or "reset display" doesn't dismiss the panel mid-glance.
    function longQuickTile(t) {
        if (!t || !t.longAction) return;
        runner.command = ["sh", "-c",
                          "setsid -f uwsm-app -- bash -c "
                          + JSON.stringify(t.longAction)
                          + " >/dev/null 2>&1"];
        runner.running = false;
        runner.running = true;
    }

    // gh CLI-backed repo search + README preview.

    property var recentEmojis: []
    property var recentEmojiData: []
    function _recordRecentEmoji(emoji) {
        var list = root.recentEmojis.slice();
        var idx = list.indexOf(emoji);
        if (idx >= 0) list.splice(idx, 1);
        list.unshift(emoji);
        if (list.length > 20) list.length = 20;
        root.recentEmojis = list;
        // Also store full data for display
        var all = EmojiData.search("");
        var data = [];
        for (var i = 0; i < list.length && i < 20; i++) {
            for (var j = 0; j < all.length; j++) {
                if (all[j].e === list[i]) { data.push(all[j]); break; }
            }
        }
        root.recentEmojiData = data;
    }

    // Items for the recents row (up to 10 recent emojis)
    readonly property var recentEmojiItems: root.recentEmojiData.slice(0, 10)

    readonly property var filteredEmojis: {
        // Guard emoji mode FIRST — without this, an empty query returns
        // all 1325 emoji entries and the Repeater creates ~8k QML objects
        // synchronously, freezing the main thread for 300-800 ms.
        if (!root.emojiMode) return [];
        const q = root.query;
        if (q.length === 0) return EmojiData.search("");
        return EmojiData.search(q);
    }

    readonly property string sectionIcon: {
        if (root.categoryFilter === "") return "";
        for (let i = 0; i < Data.categoryNav.length; i++) {
            if (Data.categoryNav[i].target === root.categoryFilter)
                return Data.categoryNav[i].icon;
        }
        return "";
    }

    // fd-backed file search + file preview. Aliases mirror the prior root
    // properties so the panel UI doesn't have to change wholesale.


    ClipboardSearch {
        id: clipSearch
        active: root.clipMode && !root.tldrMode && !root.llmMode
        selectedItem: root.filteredItems[root.selectedIndex] || null
    }
    readonly property alias clipItems:    clipSearch.items
    readonly property alias clipRunning:  clipSearch.running
    readonly property alias clipPreviewText: clipSearch.previewText
    readonly property alias clipPreviewKind: clipSearch.previewKind
    readonly property alias clipPreviewPath: clipSearch.previewPath


    // tldr-backed CLI help preview. Triggered by `$ <name>` in the query.

    // Local-LLM preview. Triggered by `? <question>` (chat) or
    // `$ <task>` (command). The mode property steers the system
    // prompt and the placeholder copy; everything else (probe,
    // streaming, unload-on-leave) is shared.

    readonly property bool previewActive: root.clipMode
    readonly property bool previewHasContent: {
        if (root.tldrMode) return root.tldrPreview !== "";
        if (root.llmMode) {
            // Probing: no content yet. Status != "ok": show the
            // install/start/pull hint as content. OK + not submitted:
            // empty (the placeholder hint shows). OK + submitted:
            // there's a streaming or completed answer.
            if (root.chatStatus === "") return false;
            if (root.chatStatus !== "ok") return true;
            if (!root.chatSubmitted) return false;
            return root.chatPreview !== "";
        }
        if (root.fileMode || root.ghMode)
            return root.previewPath !== "" || root.previewRepoUrl !== "";
        if (root.clipMode) return clipSearch.previewText !== "" || clipSearch.previewPath !== "";
        if (root.themeMode) {
            const it = root.filteredItems[root.selectedIndex];
            return !!(it && it.swatches && it.swatches.length > 0);
        }
        return false;
    }

    readonly property string homeDir: Quickshell.env("HOME")

    // Prefer any 1.0× output (external Dell). Laptop-only @ 1.25× cannot host standalone omni (Qt 6.11).
    function pickStandaloneScreen() {
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].devicePixelRatio === 1.0)
                return screens[i];
        }
        return null;
    }

    function open() {
        root._closeQueued = false;
        root.useBarEmbed = false;
        root.activeScreenIndex = -1;
        root.query = "";
        root.selectedIndex = 0;
        root.categoryFilter = "";
        // Immediately show cached default list — no delay
        root._visibleCount = 50;
        root._visibleTarget = root._defaultList.length;
        root.filteredItems = root._defaultList;
        if (root._defaultList.length > 50) _revealTimer.start();
        // Set screen imperatively to focused monitor
        var s = Quickshell.screens;
        var fm = Hyprland.focusedMonitor;
        if (fm) {
            for (var i = 0; i < s.length; i++) {
                if (s[i].name === fm.name) { panel.screen = s[i]; break; }
            }
        }
        root.visible_ = true;
        Qt.callLater(root.schedulePaletteFocus);
    }
    signal paletteFocusHook()
    function schedulePaletteFocus() {
        root.paletteFocusHook();
    }
    function close() {
        _revealTimer.stop();
        root._closeQueued = true;
        Qt.callLater(function() {
            if (!root._closeQueued) return;
            root._closeQueued = false;
            root.visible_ = false;
            root.useBarEmbed = false;
            root.activeScreenIndex = -1;
            root.query = "";
            root.selectedIndex = 0;
            root.categoryFilter = "";
            // Restore keyboard focus to the previously focused window
            focusRestore.running = false;
            focusRestore.running = true;
        });
    }

    function toggle() { if (root.visible_) close(); else open(); }
    function goUp() {
        // Step back one level. At root this is a no-op so the caller can
        // chain "goUp or close" without a branch.
        if (root.categoryFilter !== "") {
            root.categoryFilter = "";
            root.query = "";
            root.selectedIndex = 0;
            return true;
        }
        return false;
    }

    // Entering or leaving file mode resets fd state. Other category drills
    // share the same handler — clearing both is a free no-op for other drills.
    onCategoryFilterChanged: root._recomputeFiltered()
    onQueryChanged: root._recomputeFiltered()

    Connections {
        target: bookmarks
        function onFavouriteItemsChanged() { root._rebuildDefaultList(); }
    }

    // Re-filter when async clip items arrive (cliphist list is async).
    Connections {
        target: clipSearch
        function onItemsChanged() {
            if (root.clipMode) root._recomputeFiltered();
        }
    }

    // ---------- Icon resolution ----------
    // Cache icon resolution so Quickshell.iconPath() is called once per
    // unique icon name, not once per delegate.  Without this, opening the
    // default list triggers 200+ synchronous icon-path lookups that block
    // the UI thread for ~100-300ms.
    property var _iconCache: ({})
    function resolveIconUrl(raw) {
        if (!raw) return "";
        if (raw.charAt(0) === "/") return "file://" + raw;
        if (root._iconCache[raw] !== undefined) return root._iconCache[raw];
        const url = Quickshell.iconPath(raw, "");
        root._iconCache[raw] = url;
        return url;
    }

    // Pre-warm icon cache: resolve icons for all items in batches
    // of 20 per frame so the first open doesn't freeze.
    property bool _iconCachePrimed: false
    property int _iconPreWarmIndex: 0
    Timer {
        id: _iconPreWarmer
        interval: 16
        repeat: true
        onTriggered: {
            const items = root.allItems;
            const batch = 20;
            const end = Math.min(root._iconPreWarmIndex + batch, items.length);
            for (let i = root._iconPreWarmIndex; i < end; i++) {
                const raw = items[i].rawIcon;
                if (raw && raw.charAt(0) !== "/" && root._iconCache[raw] === undefined) {
                    root._iconCache[raw] = Quickshell.iconPath(raw, "");
                }
            }
            root._iconPreWarmIndex = end;
            if (end >= items.length) {
                _iconPreWarmer.stop();
                root._iconCachePrimed = true;
            }
        }
    }

    // ---------- Search index annotation ----------
    // Annotated indexes. Assigned in Component.onCompleted and in the
    // appScan handler so they stay plain `var` assignments rather than
    // re-evaluating bindings whose dependency graph would re-allocate the
    // 200+ entry array on unrelated property touches.
    property var omarchy: []
    property var nav: []
    property var allItems: []
    function _rebuildAllItems() {
        root.allItems = root.omarchy.concat(appScan.apps).concat(navbarApps.items);
        root._searchPool = root.navRows.concat(root.allItems);
    }

    // ---------- Launcher ----------
    // Matches omarchy's launch convention (see omarchy-launch-or-focus):
    //   setsid -f          fork into a new session, returning immediately
    //                      so quickshell's Process completes; the spawned
    //                      app fully detaches from quickshell's lifetime
    //   uwsm-app -- <cmd>  registers the spawn under a systemd-user scope
    //                      (omarchy convention; gives the app a managed
    //                      unit, proper cgroup, clean logout teardown)
    //   bash -c "<exec>"   lets exec lines with shell syntax (pipes,
    //                      ||, &&, redirects) work alongside plain
    //                      argv-style commands without a special case
    Process { id: runner; running: false }
    Process { id: focusRestore; running: false
        command: ["hyprctl", "dispatch", "focusurgentorlast"]
    }
    function activate(item) {
        if (!item) return;
        if (item.isCategory) {
            root.categoryFilter = item.target;
            root.query = "";
            root.selectedIndex = 0;
            return;
        }
        // Normal item — launch and close
        if (item.exec) {
            bookmarks.record(item);
            runner.command = ["sh", "-c", "cd ~ && " + item.exec];
            runner.running = false;
            runner.running = true;
            root.close();
        }
    }

    // ---------- Search ----------
    // Each query token must match somewhere in the item for the item to
    // qualify; scores stack so "thm dark" finds Theme even though neither
    // token is a prefix on its own. Uses precomputed lowercased fields
    // (`_t`/`_k`/`_c`) so a 200+ item × N-token scoring pass doesn't
    // re-lowercase the same strings on every keystroke.
    // Title-only score for the primary sort axis. When the typed query
    // hits the title, that's a strong "user wants THIS" signal and the
    // bucket competition (App vs omarchy vs theme) should happen here,
    // before keyword/category bonuses can flip the ranking.
    function primaryScore(item, tokens) {
        const title = item._t;
        let total = 0;
        for (let i = 0; i < tokens.length; i++) {
            const t = tokens[i];
            if (title.indexOf(t) === 0) total += root.scPrefix;
            else if (title.indexOf(t) >= 0) total += root.scTitle;
        }
        return total;
    }

    // Kind rank used as a tie-break after primaryScore+isCategory. Lower wins.
    // Categories chosen to satisfy "Apps before omarchy/navbar before
    // niche (TUIs, themes)" without source-tagging — the relevant
    // category strings are stable across sources.
    function kindRank(item) {
        const c = item.category;
        if (c === "App") return 1;
        if (c === "TUI") return 3;
        if (c === "THEME" || c === "ACTIVE") return 4;
        return 2;
    }

    function scoreItem(item, tokens) {
        const title = item._t;
        const kw = item._k;
        const cat = item._c;
        let total = 0;
        for (let i = 0; i < tokens.length; i++) {
            const t = tokens[i];
            let sub = 0;
            if (title.indexOf(t) === 0) sub += root.scPrefix;
            else if (title.indexOf(t) >= 0) sub += root.scTitle;
            if (kw.indexOf(t) >= 0) sub += root.scKw;
            if (cat.indexOf(t) >= 0) sub += root.scCat;
            if (sub === 0) return 0; // any token miss disqualifies
            total += sub;
        }
        return total;
    }

    readonly property var queryTokens: {
        const q = root.query.trim().toLowerCase();
        return q.length === 0 ? [] : q.split(/\s+/);
    }

    readonly property var navRows: root.nav

    // Cached default list (empty query) — rebuilt only when
    // allItems or bookmarks change, NOT on every filteredItems read.
    property var _defaultList: []
    function _rebuildDefaultList() {
        const favs = bookmarks.favouriteItems.slice(0, 5);
        const favKeys = {};
        for (let i = 0; i < favs.length; i++) {
            favKeys[Data.itemKey(favs[i])] = true;
        }
        const tail = [];
        for (let i = 0; i < root.allItems.length; i++) {
            const it = root.allItems[i];
            const c = it.category;
            if (c === "TUI" || c === "THEME" || c === "ACTIVE") continue;
            if (favKeys[Data.itemKey(it)]) continue;
            tail.push(it);
        }
        root._defaultList = root.navRows.concat(favs).concat(tail);
    }

    // Cached search pool (navRows + allItems) — rebuilt with allItems.
    property var _searchPool: []

    // Direct filtered items — no debounce, no incremental loading.
    // Empty query returns cached _defaultList immediately; scored
    // search runs inline for non-empty queries.
    property var filteredItems: []

    // Progressive reveal: show items in batches to avoid delegate
    // creation freeze. _visibleCount starts at 50 and increments
    // by 50 every frame until all items are visible.
    property int _visibleCount: 50
    property int _visibleTarget: 0
    Timer {
        id: _revealTimer
        interval: 16
        repeat: true
        onTriggered: {
            if (root._visibleCount >= root._visibleTarget) {
                _revealTimer.stop();
                return;
            }
            root._visibleCount = Math.min(root._visibleCount + 50, root._visibleTarget);
        }
    }
    function _startReveal(count) {
        root._visibleTarget = count;
        root._visibleCount = Math.min(50, count);
        if (count > 50) _revealTimer.start();
        else _revealTimer.stop();
    }

    function _recomputeFiltered() {
        if (!root.visible_) return;
        const tokens = root.queryTokens;
        const filter = root.categoryFilter;
        const cap = root.maxResults;

        // Favourites/history/proc/theme drill-ins draw from their
        // owning component; scoring still applies so typing inside the
        // drill filters live.
        let pool;
        if (root.favMode)        pool = bookmarks.favouriteItems;
        else if (root.histMode)  pool = bookmarks.historyItems;
        else if (root.procMode)  pool = root.procItems;
        else if (root.clipMode)  pool = root.clipItems;
        else if (root.themeMode) pool = root.themeItems;
        else if (filter !== "")  pool = root.allItems.filter(it => it.category === filter);
        else                     pool = root._searchPool;

        // Empty query, default view: return cached list directly (no scoring).
        if (tokens.length === 0) {
            if (root.favMode || root.histMode || root.procMode
                || root.themeMode || filter !== "") {
                const items = pool.length <= cap ? pool : pool.slice(0, cap);
                root.filteredItems = items;
                root._startReveal(items.length);
                return;
            }
            const def = root._defaultList.length <= cap
                ? root._defaultList : root._defaultList.slice(0, cap);
            root.filteredItems = def;
            root._startReveal(def.length);
            return;
        }

        // Scored search — inline, no debounce needed.
        const scored = [];
        for (let i = 0; i < pool.length; i++) {
            const it = pool[i];
            const s = root.scoreItem(it, tokens);
            if (s > 0) {
                scored.push({
                    s: s,
                    p: root.primaryScore(it, tokens),
                    item: it
                });
            }
        }
        scored.sort((a, b) => {
            if (b.p !== a.p) return b.p - a.p;
            const aCat = a.item.isCategory ? 0 : 1;
            const bCat = b.item.isCategory ? 0 : 1;
            if (aCat !== bCat) return aCat - bCat;
            const ka = root.kindRank(a.item);
            const kb = root.kindRank(b.item);
            if (ka !== kb) return ka - kb;
            if (b.s !== a.s) return b.s - a.s;
            return a.item.title.localeCompare(b.item.title);
        });
        const lim = Math.min(scored.length, cap);
        const out = new Array(lim);
        for (let j = 0; j < lim; j++) out[j] = scored[j].item;
        root.filteredItems = out;
        root._startReveal(out.length);
    }

    onFilteredItemsChanged: {
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex,
                                                  root.filteredItems.length - 1));
    }

    // ---------- Selection movement ----------
    // Single entry point for keyboard nav so arrow/Tab/Page bindings stay
    // one-liners. `wrap` toggles modulo behaviour vs. clamp — arrow + Tab
    // wrap, paging clamps (matches list-widget convention everywhere else).
    function moveSelection(delta, wrap) {
        const n = root.filteredItems.length;
        if (n === 0) return;
        let next = root.selectedIndex + delta;
        next = wrap ? ((next % n) + n) % n
                    : Math.max(0, Math.min(n - 1, next));
        root.selectedIndex = next;
    }

    // Grid-aware step for Quick mode. `delta` may exceed ±1 (arrow Up/Down
    // moves by gridCols). Clamps rather than wraps so Up from the top row
    // doesn't jump to the last row of a partial bottom row.
    function moveQuickSelection(delta) {
        const n = root.filteredQuickTiles.length;
        if (n === 0) return;
        const next = Math.max(0, Math.min(n - 1, root.selectedIndex + delta));
        root.selectedIndex = next;
    }

    Component.onCompleted: {
        root.omarchy = Data.annotate(Data.omarchyItems);
        root.nav     = Data.annotate(Data.categoryNav);
        root._rebuildAllItems();
    }
    // Rebuild default list when inputs change
    onAppsLoadedChanged: {
        root._rebuildAllItems();
        root._rebuildDefaultList();
        if (appScan.loaded && !_iconCachePrimed) {
            _iconPreWarmIndex = 0;
            _iconPreWarmer.start();
        }
    }

    // ---------- IPC ----------
    IpcHandler {
        target: "palette"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function refresh(): void { appScan.refresh(); }
        // Open OmniMenu pre-pivoted to a drill-down category (e.g. "Quick").
        // Lets Hyprland bind a shortcut straight into a category without
        // exposing the visual grid as a separate surface.
        function openCategory(cat: string): void {
            root.open();
            root.categoryFilter = cat;
        }
    }

    // ---------- Global shortcuts ----------
    // Direct wlroots global-shortcut binding. Hyprland delivers the
    // keypress over its socket straight to this running shell, so
    // SUPER+SPACE no longer pays for a fresh `qs` client process (the
    // dominant ~50-150ms of perceived "boot" before any pixel changes).
    // Bind in Hyprland with:
    //   bind = SUPER, SPACE, global, quickshell:palette-toggle
    //   bind = ALT,   SPACE, global, quickshell:palette-quick
    GlobalShortcut {
        appid: "quickshell"
        name: "palette-toggle"
        description: "Toggle omni-menu palette"
        onPressed: root.toggle()
    }
    GlobalShortcut {
        appid: "quickshell"
        name: "palette-quick"
        description: "Open omni-menu pivoted to Quick"
        onPressed: { root.open(); root.categoryFilter = "Quick"; }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!root.visible_) {
                var t = root.pickStandaloneScreen();
                if (t) panel.screen = t;
            } else if (root.useBarEmbed) {
                root.activeScreenIndex = root.laptopScreenIndex();
            }
        }
    }


    property bool useBarEmbed: false
    property int activeScreenIndex: -1
    readonly property alias omniCardContent: omniSurface

    function laptopScreenIndex() {
        var screens = Quickshell.screens;
        if (screens.length === 0) return -1;
        var fm = Hyprland.focusedMonitor;
        if (fm) {
            for (var i = 0; i < screens.length; i++) {
                if (screens[i].name === fm.name) return i;
            }
        }
        for (var j = 0; j < screens.length; j++) {
            if (screens[j].name.indexOf("eDP") >= 0) return j;
        }
        return 0;
    }

    // ---------- Panel (1.0× external) + bar-embed (laptop 1.25×) ----------
    Component {
        id: omniSurface
        Rectangle {
            id: card
            objectName: "omniCard"
            visible: true
            anchors.fill: parent
            color: Qt.rgba(root.paper.r * 0.5, root.paper.g * 0.5, root.paper.b * 0.5, 1.0)
            border.color: root.sep
            border.width: 1
            radius: root.cornerRadius
            opacity: root.useBarEmbed ? 1 : (root.visible_ ? 1 : 0)

            // Swallow clicks so the underlying dismiss MouseArea doesn't fire.
            MouseArea { anchors.fill: parent; focus: false }

            focus: root.visible_
            activeFocusOnTab: root.visible_
            Keys.onPressed: function(event) {
                // hjkl → arrow translation (Vim-style nav). Only active
                // in quickMode, where there is no typing buffer and the
                // tile grid is the sole input surface. In the main omni
                // search h/j/k/l are letters first; remapping them — even
                // conditionally on empty query — surprised users who
                // expected to start typing immediately.
                const _hjklMap = {};
                _hjklMap[Qt.Key_H] = Qt.Key_Left;
                _hjklMap[Qt.Key_J] = Qt.Key_Down;
                _hjklMap[Qt.Key_K] = Qt.Key_Up;
                _hjklMap[Qt.Key_L] = Qt.Key_Right;
                const _wrap = (e) => {
                    if (_hjklMap[e.key] === undefined) return e;
                    if (!root.quickMode) return e;
                    return { key: _hjklMap[e.key], modifiers: e.modifiers, text: e.text };
                };
                const e2 = _wrap(event);

                // When a quick tile is expanded, give its body first crack
                // at the key so arrow/Tab/Enter drive the body's own focus

                if (e2.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                } else if (root.quickMode && e2.key === Qt.Key_Left) {
                    root.moveQuickSelection(-1);
                    event.accepted = true;
                } else if (root.quickMode && e2.key === Qt.Key_Right) {
                    root.moveQuickSelection(1);
                    event.accepted = true;
                } else if (root.quickMode && e2.key === Qt.Key_Up) {
                    root.moveQuickSelection(-root.quickGridCols);
                    event.accepted = true;
                } else if (root.quickMode && e2.key === Qt.Key_Down) {
                    root.moveQuickSelection(root.quickGridCols);
                    event.accepted = true;
                } else if (root.quickMode
                           && (e2.key === Qt.Key_Tab && !(e2.modifiers & Qt.ShiftModifier))) {
                    root.moveQuickSelection(1);
                    event.accepted = true;
                } else if (root.quickMode
                           && (e2.key === Qt.Key_Backtab
                               || (e2.key === Qt.Key_Tab && (e2.modifiers & Qt.ShiftModifier)))) {
                    root.moveQuickSelection(-1);
                    event.accepted = true;
                } else if (root.llmMode && root.previewHasContent
                           && (e2.key === Qt.Key_Up || e2.key === Qt.Key_Down
                               || e2.key === Qt.Key_PageUp || e2.key === Qt.Key_PageDown
                               || e2.key === Qt.Key_Home || e2.key === Qt.Key_End
                               || e2.key === Qt.Key_Tab || e2.key === Qt.Key_Backtab)) {
                    // chat / command mode: same scroll routing as
                    // tldr mode below.
                    // List nav is a no-op here (single synthetic row).
                    const f = previewPaneInstance.chatFlickable;
                    const max = Math.max(0, f.contentHeight - f.height);
                    const line = 18;
                    const page = Math.max(line, f.height * 0.9);
                    let dy = 0;
                    if (e2.key === Qt.Key_Up
                        || (e2.key === Qt.Key_Tab && (e2.modifiers & Qt.ShiftModifier))
                        || e2.key === Qt.Key_Backtab) dy = -line;
                    else if (e2.key === Qt.Key_Down
                             || (e2.key === Qt.Key_Tab && !(e2.modifiers & Qt.ShiftModifier))) dy = line;
                    else if (e2.key === Qt.Key_PageUp)   dy = -page;
                    else if (e2.key === Qt.Key_PageDown) dy = page;
                    else if (e2.key === Qt.Key_Home) { f.contentY = 0; event.accepted = true; return; }
                    else if (e2.key === Qt.Key_End)  { f.contentY = max; event.accepted = true; return; }
                    f.contentY = Math.max(0, Math.min(max, f.contentY + dy));
                    event.accepted = true;
                } else if (root.tldrMode && root.tldrPreview !== ""
                           && (e2.key === Qt.Key_Up || e2.key === Qt.Key_Down
                               || e2.key === Qt.Key_PageUp || e2.key === Qt.Key_PageDown
                               || e2.key === Qt.Key_Home || e2.key === Qt.Key_End
                               || e2.key === Qt.Key_Tab || e2.key === Qt.Key_Backtab)) {
                    // tldr mode has a single synthetic row, so list nav is
                    // a no-op. Route arrow/page/home/end (and Tab/Shift+Tab,
                    // which would otherwise wrap the same row to itself) to
                    // the preview Flickable instead.
                    const f = previewPaneInstance.tldrFlickable;
                    const max = Math.max(0, f.contentHeight - f.height);
                    const line = 18;
                    const page = Math.max(line, f.height * 0.9);
                    let dy = 0;
                    if (e2.key === Qt.Key_Up
                        || (e2.key === Qt.Key_Tab && (e2.modifiers & Qt.ShiftModifier))
                        || e2.key === Qt.Key_Backtab) dy = -line;
                    else if (e2.key === Qt.Key_Down
                             || (e2.key === Qt.Key_Tab && !(e2.modifiers & Qt.ShiftModifier))) dy = line;
                    else if (e2.key === Qt.Key_PageUp)   dy = -page;
                    else if (e2.key === Qt.Key_PageDown) dy = page;
                    else if (e2.key === Qt.Key_Home) { f.contentY = 0; event.accepted = true; return; }
                    else if (e2.key === Qt.Key_End)  { f.contentY = max; event.accepted = true; return; }
                    f.contentY = Math.max(0, Math.min(max, f.contentY + dy));
                    event.accepted = true;
                } else if (root.emojiMode
                           && (e2.key === Qt.Key_Down || e2.key === Qt.Key_Up
                               || e2.key === Qt.Key_Left || e2.key === Qt.Key_Right)) {
                    // Grid-based emoji navigation. Down/Up step by one
                    // row; Left/Right by one cell.
                    var delta2 = 0;
                    if (e2.key === Qt.Key_Down)      delta2 = emojiGrid.columns;
                    else if (e2.key === Qt.Key_Up)   delta2 = -emojiGrid.columns;
                    else if (e2.key === Qt.Key_Right) delta2 = 1;
                    else if (e2.key === Qt.Key_Left)  delta2 = -1;
                    emojiGrid.moveSelection(delta2);
                    event.accepted = true;
                } else if (root.emojiMode
                           && (e2.key === Qt.Key_Return || e2.key === Qt.Key_Enter)) {
                    // Enter picks the selected emoji
                    var idx2 = emojiGrid.selectedIndex;
                    if (idx2 >= 0 && idx2 < root.filteredEmojis.length) {
                        var ed = root.filteredEmojis[idx2];
                        emojiGrid.picked(ed.e, ed.n || "");
                    }
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Down
                           || (e2.key === Qt.Key_Tab && !(e2.modifiers & Qt.ShiftModifier))) {
                    // Tab + Down step forward, Shift+Tab + Up step backward,
                    // both wrap. Paging clamps (see Key_PageDown). Matches
                    // launcher convention everywhere else.
                    root.blockMouse();
                    root.moveSelection(1, true);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Up
                           || e2.key === Qt.Key_Backtab
                           || (e2.key === Qt.Key_Tab && (e2.modifiers & Qt.ShiftModifier))) {
                    root.blockMouse();
                    root.moveSelection(-1, true);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_PageDown) {
                    root.blockMouse();
                    root.moveSelection(8, false);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_PageUp) {
                    root.blockMouse();
                    root.moveSelection(-8, false);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Home) {
                    root.blockMouse();
                    root.selectedIndex = 0;
                    event.accepted = true;
                } else if (e2.key === Qt.Key_End) {
                    root.blockMouse();
                    root.selectedIndex = Math.max(0, root.filteredItems.length - 1);
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Return || e2.key === Qt.Key_Enter) {
                    if (root.quickMode) {
                        const t = root.filteredQuickTiles[root.selectedIndex];
                        if (t) root.expandTile(t);
                    } else {
                        const it = root.filteredItems[root.selectedIndex];
                        if (it) root.activate(it);
                    }
                    event.accepted = true;
                } else if (e2.key === Qt.Key_Backspace) {
                    // Backspace deletes a char first; once the query is
                    // empty it walks back up one level so the same key
                    // unwinds both the typed query and the breadcrumb.
                    if (root.query.length > 0) root.query = root.query.slice(0, -1);
                    else root.goUp();
                    event.accepted = true;
                } else if (e2.key === Qt.Key_S && (e2.modifiers & Qt.ControlModifier)) {
                    const it = root.filteredItems[root.selectedIndex];
                    if (it && !it.isCategory && !it.isTldr && !it.isOllama) bookmarks.toggleFavourite(it);
                    event.accepted = true;
                } else if ((e2.modifiers & Qt.ControlModifier)
                           && (e2.key === Qt.Key_Plus || e2.key === Qt.Key_Equal
                               || e2.key === Qt.Key_Minus)) {
                    // Ctrl++ / Ctrl+- nudge the omni-menu font scale;
                    // Ctrl+= resets to default. Plus is reached via
                    // Shift+= on US layouts (Qt delivers Qt.Key_Plus),
                    // and via a dedicated key on numpads / EU layouts.
                    if (e2.key === Qt.Key_Plus) root.bumpFontScale(+0.1);
                    else if (e2.key === Qt.Key_Minus) root.bumpFontScale(-0.1);
                    else /* Key_Equal without Shift */ root.fontScale = 1.0;
                    event.accepted = true;
                } else if (e2.key === Qt.Key_C && (e2.modifiers & Qt.ControlModifier)
                           && root.llmMode && root.chatPreview !== "") {
                    // Ctrl+C: if the user dragged a selection in the
                    // rendered RichText edit, copy that (lossy — Qt
                    // strips inline `code` backticks during conversion,
                    // but it's what they asked for). With no selection,
                    // copy the full raw markdown from the hidden plain-
                    // text shadow so pasted commands keep their syntax.
                    if (previewPaneInstance.chatEdit.selectedText.length > 0) {
                        previewPaneInstance.chatEdit.copy();
                    } else {
                        previewPaneInstance.chatPlain.selectAll();
                        previewPaneInstance.chatPlain.copy();
                        previewPaneInstance.chatPlain.deselect();
                    }
                    event.accepted = true;
                } else if (e2.key === Qt.Key_C && (e2.modifiers & Qt.ControlModifier)
                           && root.tldrMode && root.tldrPreview !== "") {
                    // Ctrl+C in tldr mode: copy the active selection if
                    // there is one, otherwise copy the whole rendered
                    // preview. The TextEdit's `copy()` works without
                    // active focus, so the search input keeps keystrokes.
                    if (previewPaneInstance.tldrEdit.selectedText.length > 0) {
                        previewPaneInstance.tldrEdit.copy();
                    } else {
                        previewPaneInstance.tldrEdit.selectAll();
                        previewPaneInstance.tldrEdit.copy();
                        previewPaneInstance.tldrEdit.deselect();
                    }
                    event.accepted = true;
                } else if (!root.quickMode && event.text && event.text.length === 1) {
                    const ch = event.text;
                    // Printable range; lets letters, digits, and spaces in,
                    // keeps modifier-driven control codes out. Skipped in
                    // quickMode — there's no search field to feed.
                    if (ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) !== 127) {
                        root.query += ch;
                        root.selectedIndex = 0;
                        event.accepted = true;
                    }
                }
            }

            Column {
                id: cardCol
                anchors.fill: parent
                anchors.margins: 17
                spacing: 12

                Omni.SearchInput { omni: root }

                Rectangle {
                    visible: !root.quickMode
                    width: parent.width
                    height: 1
                    color: root.sep
                }

                Item {
                    id: listArea
                    visible: !root.quickMode
                    width: parent.width
                    height: visible
                        ? Math.max(60, card.height - 34 - 12 * 2)
                        : 0
                    clip: true

                    readonly property real listFraction: root.previewActive ? 0.44 : 1.0

                    Omni.ResultList {
                        id: resultListInstance
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: parent.width * (root.emojiMode ? 0 : listArea.listFraction)
                        visible: !root.emojiMode
                        omni: root
                        bookmarks: bookmarks
                    }

                    // Recent emojis row
                    Flow {
                        id: recentRow
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 10
                        spacing: 4
                        visible: root.emojiMode && root.recentEmojiItems.length > 0 && root.query.length === 0

                        Repeater {
                            model: root.recentEmojiItems
                            Rectangle {
                                width: 40
                                height: 40
                                radius: 6
                                color: recMouse.containsMouse
                                    ? (root.rowHi || "#40ffffff")
                                    : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData ? modelData.e : ""
                                    font.pixelSize: 28
                                }
                                MouseArea {
                                    id: recMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (modelData && modelData.e) {
                                            root._recordRecentEmoji(modelData.e);
                                            root.close();
                                            Qt.callLater(function() {
                                                var proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
                                                proc.command = ["sh", "-c", "wtype -- \"" + modelData.e + "\""];
                                                proc.running = false;
                                                proc.running = true;
                                            });
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Emoji grid (below recents)
                    Omni.EmojiGrid {
                        id: emojiGrid
                        anchors.top: recentRow.visible ? recentRow.bottom : parent.top
                        anchors.topMargin: recentRow.visible ? 4 : 0
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: parent.width
                        visible: root.emojiMode
                        omni: root
                        model: root.filteredEmojis
                        onPicked: (emoji, name) => {
                            root._recordRecentEmoji(emoji);
                            root.close();
                            // Type emoji after close so target window regains focus
                            Qt.callLater(function() {
                                var proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
                                proc.command = ["sh", "-c", "wtype -- \"" + emoji + "\""];
                                proc.running = false;
                                proc.running = true;
                            });
                        }
                    }

                    Rectangle {
                        visible: root.previewActive && !root.emojiMode && resultListInstance.width < listArea.width
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: resultListInstance.right
                        anchors.right: parent.right
                        width: parent.width * (1 - listArea.listFraction)
                        color: "transparent"

                        Omni.PreviewPane {
                            id: previewPaneInstance
                            anchors.fill: parent
                            anchors.margins: 13
                            omni: root
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        id: panel
        visible: true
        color: "transparent"
        width: root.visible_ ? (root.previewActive ? 1100 : 720) : 0
        height: root.visible_ ? Math.round(Math.min(Quickshell.screens.length > 0 ? Quickshell.screens[0].height * 0.68 : 1080, 800)) : 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: root.visible_ ? "omni-menu" : "omni-menu-hidden"
        WlrLayershell.keyboardFocus: root.visible_ && !root.useBarEmbed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        function focusOmniCard() {
            panelFocusRoot.forceActiveFocus();
            const item = panelLoader.item;
            if (!item) return;
            const stack = [item];
            while (stack.length > 0) {
                const node = stack.pop();
                if (node.objectName === "omniCard" && node.forceActiveFocus) {
                    node.forceActiveFocus();
                    return;
                }
                const kids = node.children;
                if (kids) {
                    for (let i = 0; i < kids.length; i++)
                        stack.push(kids[i]);
                }
            }
        }

        Timer {
            id: panelFocusTimer
            interval: 16
            repeat: false
            onTriggered: panel.focusOmniCard()
        }

        Connections {
            target: root
            function onPaletteFocusHook() { panelFocusTimer.restart(); }
            function onVisibleChanged() {
                if (root.visible_ && !root.useBarEmbed)
                    panelFocusTimer.restart();
            }
        }

        FocusScope {
            id: panelFocusRoot
            visible: root.visible_
            opacity: root.visible_ ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            anchors.fill: parent
            focus: root.visible_ && !root.useBarEmbed

            Loader {
                id: panelLoader
                anchors.fill: parent
                active: true
                sourceComponent: omniSurface
                onLoaded: { if (root.visible_ && !root.useBarEmbed) panelFocusTimer.restart(); }
            }
        }
    }
}