// webtorrent-hook.js — mpv hook for webtorrent streaming
// Intercepts .torrent files and magnet links, hands them to the
// webtorrent server, and shows the same OSD stats as webtorrent-mpv-hook.

var WEBTORRENT_BIN = '/home/pavel/.local/bin/webtorrent'

var active          = false
var initiallyActive = false
var overlayText     = ''
var handlersSetUp   = false
var wtPending       = false  // true while a webtorrent subprocess is in flight

// ─── IPC socket ─────────────────────────────────────────────────────
// Ensure mpv has an IPC socket so the webtorrent server can push back.

function ensureIpcSocket() {
  if (!mp.get_property('input-ipc-server')) {
    mp.set_property('input-ipc-server', '/tmp/mpvsocket')
  }
}

// ─── OSD ────────────────────────────────────────────────────────────

function keyPressHandler() {
  if (active || initiallyActive) {
    clearOverlay()
  } else {
    showOverlay()
  }
}

function showOverlay() {
  active = true
  printOverlay()
}

function printOverlay() {
  if (!overlayText) return
  if (active || initiallyActive) {
    var expanded = mp.command_native(['expand-text', overlayText], '')
    mp.osd_message(expanded, 10)
  }
}

function clearOverlay() {
  active = false
  initiallyActive = false
  mp.osd_message('', 0)
}

// ─── Script-message handlers ─────────────────────────────────────────
// The webtorrent server sends these via mpv IPC.

function onData(text) {
  overlayText = text
  printOverlay()
}

function onPlaylist(json) {
  var data
  try { data = JSON.parse(json) } catch (e) { return }
  var urls  = data.urls
  var names = data.names || []
  if (!urls || urls.length === 0) return

  // Write a temporary M3U so mpv reads #EXTINF titles and shows human-readable
  // names in the playlist — same mechanism as loading /latest.m3u directly.
  var m3u = '#EXTM3U\n'
  for (var i = 0; i < urls.length; i++) {
    m3u += '#EXTINF:-1,' + (names[i] || '') + '\n' + urls[i] + '\n'
  }
  mp.utils.write_file('file:///tmp/webtorrent-playlist.m3u', m3u)

  // loadlist parses the file and replaces the playlist before returning.
  // mpv's watch-later handles resuming to the right episode and time position.
  mp.commandv('loadlist', '/tmp/webtorrent-playlist.m3u', 'replace')
}

function onFileLoaded() {
  overlayText = ''
  initiallyActive = false
  clearOverlay()
}

// ─── Lifecycle ───────────────────────────────────────────────────────

function killWebtorrent() {
  mp.command_native({
    name: 'subprocess',
    args: ['pkill', '-TERM', '-f', WEBTORRENT_BIN],
    playback_only: false,
    capture_stdout: false,
    capture_stderr: false
  })
}

mp.register_event('shutdown', killWebtorrent)

// ─── Subprocess callback ─────────────────────────────────────────────

function onWebtorrentExit(success, result) {
  wtPending = false
  // When the server was already running, webtorrent --hook exits quickly
  // with code 0 after sending the load command — that is normal, not an error.
  if (!success) {
    mp.msg.error('webtorrent: process failed to start')
  } else if (result && result.status && result.status !== 0) {
    mp.msg.error('webtorrent: exited with status ' + result.status +
      (result.stderr ? ' — ' + result.stderr.trim() : ''))
  } else if (result && result.stderr && result.stderr.trim()) {
    mp.msg.warn('webtorrent: ' + result.stderr.trim())
  }
}

// ─── Hook ────────────────────────────────────────────────────────────

function onLoadHook() {
  var url = mp.get_property('stream-open-filename', '')

  // Strip any protocol prefix that ends up before a magnet: URI
  var magnetIdx = url.indexOf('magnet:')
  if (magnetIdx > 0) url = url.substring(magnetIdx)

  var isTorrent = /\.torrent$/i.test(url) || /^magnet:/i.test(url)

  // Also accept raw info-hashes (40-char hex or 32-char base32)
  if (!isTorrent) {
    var basename = url.split('/').pop() || ''
    if (/^[0-9A-F]{40}$/i.test(basename) || /^[0-9A-Z]{32}$/i.test(basename)) {
      if (!mp.utils.file_info(url)) isTorrent = true
    }
  }

  if (!isTorrent) return

  // Store original torrent path so navigator.lua can highlight the .torrent file
  mp.set_property('user-data/webtorrent-source', url)

  mp.msg.info('webtorrent-hook: intercepting ' + url)

  // Redirect the stream to nothing; we will load the real URLs via playlist.
  mp.set_property('stream-open-filename', 'null://')
  mp.set_property('idle', 'yes')
  mp.set_property('force-window', 'yes')
  mp.set_property('keep-open', 'yes')
  mp.command_native(['script-message-to', 'osc', 'osc-idlescreen', 'no', 'yes'])

  // Register handlers and key binding once for the whole mpv session.
  if (!handlersSetUp) {
    handlersSetUp = true
    ensureIpcSocket()
    mp.register_script_message('osd-data', onData)
    mp.register_script_message('playlist', onPlaylist)
    mp.register_event('file-loaded', onFileLoaded)
    mp.add_key_binding('p', 'wt-toggle-info', keyPressHandler)
  }

  // Show a "Loading…" overlay immediately while the torrent is fetched.
  initiallyActive = true
  active = false
  overlayText = '${osd-ass-cc/0}{\\r}{\\an7}{\\fs8}{\\fn sans}' +
    '{\\1c&HFFFFFF&}{\\bord0.8}{\\3c&H262626&}' +
    'Loading torrent\u2026${osd-ass-cc/1}'
  printOverlay()

  // Guard: if a webtorrent subprocess is already in flight, don't spawn another.
  // This breaks any feedback loop where a failed stream causes on_load to re-fire.
  if (wtPending) {
    mp.msg.warn('webtorrent-hook: spawn already in progress, ignoring duplicate on_load')
    return
  }

  wtPending = true

  // Start the server (or send to the already-running server).
  // In either case webtorrent --hook will push 'playlist' and 'osd-data'
  // messages back to mpv via the IPC socket.
  mp.command_native_async({
    name: 'subprocess',
    args: [WEBTORRENT_BIN, '--hook', url],
    playback_only: false,
    capture_stderr: true
  }, onWebtorrentExit)
}

mp.add_hook('on_load', 50, onLoadHook)
