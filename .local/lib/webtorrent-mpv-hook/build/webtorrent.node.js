var __read = (this && this.__read) || function (o, n) {
    var m = typeof Symbol === "function" && o[Symbol.iterator];
    if (!m) return o;
    var i = m.call(o), r, ar = [], e;
    try {
        while ((n === void 0 || n-- > 0) && !(r = i.next()).done) ar.push(r.value);
    }
    catch (error) { e = { error: error }; }
    finally {
        try {
            if (r && !r.done && (m = i["return"])) m.call(i);
        }
        finally { if (e) throw e.error; }
    }
    return ar;
};
var __spreadArray = (this && this.__spreadArray) || function (to, from, pack) {
    if (pack || arguments.length === 2) for (var i = 0, l = from.length, ar; i < l; i++) {
        if (ar || !(i in from)) {
            if (!ar) ar = Array.prototype.slice.call(from, 0, i);
            ar[i] = from[i];
        }
    }
    return to.concat(ar || Array.prototype.slice.call(from));
};
var _a;
import WebTorrent from 'webtorrent';
import memoryChunkStore from 'memory-chunk-store';
import net from 'net';
import convert from 'convert-units';
import { MpvJsonIpc } from 'mpv-json-ipc';
process.title = 'webtorrent-mpv-hook';
process.on('SIGINT', exit);
process.on('SIGTERM', exit);
process.on('uncaughtException', error);
process.on('unhandledRejection', error);
var options = JSON.parse((_a = process.argv[2]) !== null && _a !== void 0 ? _a : '{}');
if (process.platform === 'win32' && !options.socketName.startsWith("\\\\.\\pipe\\")) {
    options.socketName = "\\\\.\\pipe\\" + options.socketName;
}
var textStyle = [
    "{\\r}{\\an7}",
    "{\\fs".concat(Math.floor(options.font_size), "}"),
    "{\\fn".concat(options.font, "}"),
    "{\\bord".concat(options.border_size, "}"),
    "{\\3c&H".concat(options.border_color, "&}"),
    "{\\1c&H".concat(options.font_color, "&}"),
    "{\\alpha&H".concat(options.alpha, "&}"),
    "{\\xshad".concat(options.shadow_x_offset, "}"),
    "{\\yshad".concat(options.shadow_y_offset, "}"),
    "{\\4c&H".concat(options.shadow_color, "&}")
].join('');
var exiting = false;
var socket;
var jsonIpc;
var currentFile;
var assStart = '${osd-ass-cc/0}';
var assStop = '${osd-ass-cc/1}';
connectMpv();
var client = new WebTorrent({
    maxConns: options.maxConns,
    utp: options.utp,
    dht: options.dht,
    lsd: options.lsd,
    downloadLimit: options.downloadLimit,
    uploadLimit: options.uploadLimit
});
client.on('error', error);
var torrent = client.add(options.torrentId, {
    path: options.path,
    store: options.path === 'memory' ? memoryChunkStore : undefined
});
torrent.on('infoHash', function () { return log('Info hash:', torrent.infoHash); });
torrent.on('metadata', function () { return log('Metadata downloaded'); });
var server = client.createServer();
server.server.on('error', serverError);
server.listen(options.port);
function serverError(err) {
    if (err.code === 'EADDRINUSE' || err.code === 'EACCES') {
        server.destroy();
        client._server = undefined;
        server = client.createServer();
        server.server.on('error', serverError);
        server.listen(0);
        return;
    }
    return error(err);
}
function connectMpv() {
    socket = net.createConnection(options.socketName);
    socket.unref();
    jsonIpc = new MpvJsonIpc(socket);
    socket.on('connect', function () {
        updateCurrentFile();
        sendOverlay();
        setInterval(updateCurrentFile, 500);
        setInterval(sendOverlay, 500);
        if (torrent.ready) {
            startPlayback();
        }
        else {
            torrent.once('ready', startPlayback);
        }
    });
}
function updateCurrentFile() {
    void (jsonIpc.command('get_property', 'path').then(function (res) { return currentFile = res.data; }));
}
function startPlayback() {
    var _a;
    log('Ready for playback');
    var port = ((_a = server === null || server === void 0 ? void 0 : server.server) === null || _a === void 0 ? void 0 : _a.address()).port;
    var sortedFiles = __spreadArray([], __read(torrent.files), false).sort(function (a, b) { return a.path.localeCompare(b.path, undefined, { numeric: true }); });
    var playlist = sortedFiles.map(function (file) { return "http://localhost:".concat(port, "/webtorrent/").concat(torrent.infoHash, "/").concat(file.path.replace(/\\/g, '/').split('/').map(encodeURI).join('/')); });
    void (jsonIpc.command('script-message-to', 'webtorrent', 'playlist', JSON.stringify(playlist)));
}
function sendOverlay() {
    var _a, _b;
    var B = function (text) { return '{\\b1}' + text + '{\\b0}'; };
    var raw = function (text) { return assStop + text.replace(/\$/g, '$$$$') + assStart; };
    var bar = buildProgressBar(torrent.pieces);
    var progress = Math.floor(Math.max(Math.min(torrent.progress, 1), 0) * 1000) / 10;
    var downloaded = formatNumber(torrent.downloaded, 'B', 2);
    var uploaded = formatNumber(torrent.uploaded, 'B', 2);
    var size = formatNumber(torrent.length, 'B', 2);
    var timeRemaining = torrent.timeRemaining ? formatNumber(torrent.timeRemaining, 'ms', 1) : '';
    var download = formatNumber(torrent.downloadSpeed, 'B', 2) + '/s';
    var upload = formatNumber(torrent.uploadSpeed, 'B', 2) + '/s';
    var ratio = torrent.uploaded / torrent.downloaded;
    var lines = [
        "".concat(B('Torrent:'), "  ").concat(raw((_b = (_a = torrent.name) !== null && _a !== void 0 ? _a : torrent.infoHash) !== null && _b !== void 0 ? _b : '')),
        "  ".concat(B('Progress:'), "  ").concat(bar, "  ").concat(progress === 100 ? progress : progress.toFixed(1), "%"),
        "  ".concat(B('Downloaded:'), "  ").concat(downloaded.padEnd(10, '\u2003'), "  ").concat(B('Size:'), "  ").concat(size.padEnd(10, '\u2003'), "  ").concat(B('Uploaded:'), "  ").concat(uploaded),
        "  ".concat(B('Download:'), "  ").concat(download.padEnd(10, '\u2003'), "  ").concat(B('Upload:'), "  ").concat(upload),
        "  ".concat(B('Time remaining:'), "  ").concat(timeRemaining),
        "  ".concat(B('Ratio:'), "  ").concat((ratio || 0).toFixed(2)),
        "  ".concat(B('Peers:'), "  ").concat(torrent.numPeers),
    ];
    if (currentFile) {
        var match = /http:\/\/localhost:\d+\/webtorrent\/(.+)/.exec(currentFile);
        var pathname = match === null || match === void 0 ? void 0 : match[1];
        if (pathname) {
            var _c = __read(pathname.split('/')), _filePath = _c.slice(1);
            var filePath_1 = decodeURI(_filePath.join('/'));
            var file = torrent.files.find(function (file) { return file.path.replace(/\\/g, '/') === filePath_1; });
            if (file) {
                var startPiece = Math.floor(file.offset / torrent.pieceLength | 0);
                var endPiece = Math.ceil((file.offset + file.length - 1) / torrent.pieceLength | 0);
                var pieces = torrent.pieces.slice(startPiece, endPiece + 1);
                var _downloaded = Math.max(Math.min(torrent.downloaded, file.downloaded), 0);
                var bar_1 = buildProgressBar(pieces);
                var progress_1 = Math.floor(Math.max(Math.min(file.progress, 1), 0) * 1000) / 10;
                var downloaded_1 = formatNumber(_downloaded, 'B', 2);
                var size_1 = formatNumber(file.length, 'B', 2);
                lines.push.apply(lines, [
                    '',
                    "".concat(B('File:'), "  ").concat(raw(file.name)),
                    "  ".concat(B('Progress:'), "  ").concat(bar_1, "  ").concat(progress_1 === 100 ? progress_1 : progress_1.toFixed(1), "%"),
                    "  ".concat(B('Downloaded:'), "  ").concat(downloaded_1.padEnd(10, '\u2003'), "  ").concat(B('Size:'), "  ").concat(size_1)
                ]);
            }
        }
    }
    void (jsonIpc.command('script-message-to', 'webtorrent', 'osd-data', assStart + textStyle + lines.join('\n') + assStop));
}
function formatNumber(value, unit, fractionDigits) {
    if (fractionDigits === void 0) { fractionDigits = 0; }
    value = value || 0;
    var res = convert(value).from(unit).toBest();
    return res.val.toFixed(fractionDigits) + ' ' + res.unit;
}
function buildProgressBar(pieces) {
    var fullBar = pieces.map(function (p) { return p ? 1 - (p.missing / p.length) : 1; });
    var barSize = 50;
    var bar = [];
    var sumFn = function (acc, cur) { return acc + cur; };
    if (fullBar.length > barSize) {
        var interval = fullBar.length / barSize;
        for (var n = 0; n <= (fullBar.length - 1); n += interval) {
            var i = Math.floor(n);
            var i2 = Math.floor(n + interval);
            var parts = fullBar.slice(i, i2);
            var sum = parts.reduce(sumFn, 0);
            bar.push(sum / parts.length);
        }
    }
    else {
        bar = fullBar;
    }
    var barText = bar.map(function (p) {
        if (p >= 1) {
            return '█';
        }
        else if (p >= 2 / 3) {
            return '▓';
        }
        else if (p >= 1 / 3) {
            return '▒';
        }
        else if (p > 0) {
            return '░';
        }
        else {
            return "{\\alpha&HCC&}{\\3a&HFF&}\u2588{\\alpha&H".concat(options.alpha, "&}");
        }
    }).join('');
    return "{\\fn".concat(options.font_mono, "}{\\fscy80}{\\fscx80}").concat(barText, "{\\fscy}{\\fscx}{\\fn").concat(options.font, "}");
}
function log() {
    var args = [];
    for (var _i = 0; _i < arguments.length; _i++) {
        args[_i] = arguments[_i];
    }
    void (jsonIpc.command.apply(jsonIpc, __spreadArray(['script-message-to', 'webtorrent', 'info'], __read(args), false)));
}
function exit() {
    if (exiting) {
        return;
    }
    exiting = true;
    process.removeListener('SIGINT', exit);
    process.removeListener('SIGTERM', exit);
    server.close(function () {
        client.destroy(function () {
            process.exit(0);
        });
    });
}
function error(error) {
    if (typeof error === 'string') {
        error = new Error(error);
    }
    console.error(error.toString());
    process.exit(1);
}
