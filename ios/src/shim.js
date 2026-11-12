/* CloudFlareScan iOS — Wails runtime shim
 * 提供 window.go.main.App.* / window.runtime.* 两个对象，
 * 把原版 dist 里的 Wails 调用原样转成 WKScriptMessage。
 * 原前端 JS 一行不改。
 */
(function () {
    var DEBUG = false;
    function report(m) {
        if (!DEBUG) return;
        try {
            window.webkit.messageHandlers.cfs.postMessage({
                id: 0, method: 'Log', args: [String(m)]
            });
        } catch (e) { }
    }
    function reportError(m) {
        try {
            window.webkit.messageHandlers.cfs.postMessage({
                id: 0, method: 'Log', args: [String(m)]
            });
        } catch (e) { }
    }
    window.__cfs_report = report;
    window.addEventListener('error', function (e) {
        reportError('JS ERROR: ' + (e.message || '?') + ' @' + (e.filename || '?') + ':' + (e.lineno || 0));
    });
    window.addEventListener('unhandledrejection', function (e) {
        var r = e.reason;
        reportError('JS REJECT: ' + (r && r.message ? r.message : String(r)));
    });

    var seq = 0;
    var pend = {};
    var H = {};

    function call(method, args) {
        return new Promise(function (resolve, reject) {
            var id = ++seq;
            pend[id] = { res: resolve, rej: reject };
            try { report('CALL ' + method + '(' + JSON.stringify(args) + ')'); } catch (e) { }
            try {
                window.webkit.messageHandlers.cfs.postMessage({
                    id: id, method: method, args: args
                });
            } catch (e) {
                delete pend[id];
                reject(String(e));
            }
        });
    }

    window.__cfs_resolve = function (id, ok, value) {
        var p = pend[id];
        if (!p) return;
        delete pend[id];
        if (ok) p.res(value); else p.rej(value);
    };

    window.__cfs_emit = function (name, args) {
        var list = H[name];
        if (!list || !list.length) return;
        for (var i = 0; i < list.length; i++) {
            try { list[i].apply(null, args || []); } catch (e) { }
        }
    };

    window.go = {
        main: {
            App: {
                StartScan: function () { return call('StartScan', [].slice.call(arguments)); },
                StopScan: function () { return call('StopScan', []); },
                StartFullSpeedTest: function () { return call('StartFullSpeedTest', [].slice.call(arguments)); },
                StartRegionSpeedTest: function () { return call('StartRegionSpeedTest', [].slice.call(arguments)); },
                StopSpeedTest: function () { return call('StopSpeedTest', []); },
                ExportResults: function () { return call('ExportResults', [].slice.call(arguments)); }
            }
        }
    };

    window.runtime = {
        EventsOnMultiple: function (name, cb) {
            (H[name] = H[name] || []).push(cb);
            return function () { window.runtime.EventsOff(name); };
        },
        EventsOff: function (name) { delete H[name]; },
        EventsEmit: function () { }
    };

    /* file:// 源下 navigator.clipboard 不可用，改走原生 UIPasteboard */
    try {
        Object.defineProperty(navigator, 'clipboard', {
            configurable: true,
            value: {
                writeText: function (t) {
                    try {
                        window.webkit.messageHandlers.cfs.postMessage({
                            id: 0, method: 'Copy', args: [String(t)]
                        });
                    } catch (e) { }
                    return Promise.resolve();
                },
                readText: function () { return Promise.reject('unsupported'); }
            }
        });
    } catch (e) { }

    document.addEventListener('click', function (e) {
        var t = e.target;
        var label = (t && (t.textContent || '').trim().slice(0, 18)) || (t && t.className) || '?';
        report('CLICK ' + label);
    }, true);

    /* 禁止双击缩放与长按菜单 */
    document.addEventListener('gesturestart', function (e) { e.preventDefault(); }, { passive: false });
    document.addEventListener('dblclick', function (e) { e.preventDefault(); }, { passive: false });

    if (DEBUG) {
        report('shim ready: go=' + (typeof window.go) + ' runtime=' + (typeof window.runtime)
            + ' readyState=' + document.readyState);
    }
})();
