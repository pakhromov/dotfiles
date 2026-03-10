#!/usr/bin/env node
import path from 'path';
import { fileURLToPath } from 'url';
import os from 'os';
import fs from 'fs';
var __dirname = path.dirname(fileURLToPath(import.meta.url));
var target = path.join(__dirname, '..', 'build', 'webtorrent.js');
var link = path.join(getScriptFolder(), 'webtorrent.js');
var pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf-8'));
console.log([
    "webtorrent-mpv-hook v".concat(pkg.version),
    '',
    'You need to symlink the script file to your mpv scripts folder:',
    '',
    "  ".concat(os.platform() === 'win32' ? "mklink \"".concat(link, "\" \"").concat(target, "\"\n  or\n  New-Item -ItemType SymbolicLink -Path \"").concat(link, "\" -Target \"").concat(target, "\"") : "ln -s \"".concat(target, "\" \"").concat(link, "\"")),
    '',
    'You can then run "mpv <torrent-id>" to start streaming.',
    ''
].join('\n'));
function getScriptFolder() {
    var mpvHome;
    if (os.platform() === 'win32') {
        mpvHome = process.env['MPV_HOME'] || path.join(process.env['APPDATA'] || '%APPDATA%', 'mpv');
    }
    else {
        mpvHome = process.env['MPV_HOME'];
        if (!mpvHome) {
            var xdgConfigHome = process.env['XDG_CONFIG_HOME'] || '$HOME/.config';
            mpvHome = path.join(xdgConfigHome, 'mpv');
        }
    }
    return path.join(mpvHome, 'scripts');
}
