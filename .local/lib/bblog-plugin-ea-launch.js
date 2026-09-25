/**
 * BBLog plugin: enable "Join server" on Linux.
 *
 * Paste into BBLog options -> General -> Plugins -> plugin editor, tick the
 * plugin editor active, and reload Battlelog.
 *
 * Why this is needed: Battlelog decides server-side whether your browser may
 * launch games and returns that as allowRunGame on the persona. On Linux it
 * says false, so the join flow shows "Unable to launch the game from this
 * device" before it ever tries. The actual launch path - an HTTP POST to the
 * EA app on 127.0.0.1:3215 - works fine under Wine; only this flag blocks it.
 *
 * This re-fetches your real persona from Battlelog and puts it in the page's
 * cache with allowRunGame set, so the normal join flow proceeds.
 *
 * Requires: EA app running and logged in, and Battlelog launch mode set to the
 * EA app (visit /bf4/profile/setLaunchMode/2/ once).
 */
(function () {
    'use strict';

    var BF4 = 2048;          // Battlelog's internal game id (games.WARSAW)
    var lastTry = 0;

    function seed() {
        if (typeof window.launcher === 'undefined' || !window.launcher.playablePersona) return;

        var cached = window.launcher.playablePersona[BF4];
        if (cached && cached.allowRunGame === true) return;

        var now = Date.now();
        if (now - lastTry < 2000) return;
        lastTry = now;

        fetch('/bf4/launcher/playablepersona/', {
            cache: 'no-store',
            credentials: 'same-origin'
        })
            .then(function (r) { return r.json(); })
            .then(function (d) {
                var persona = d && d.data;
                if (!persona || !persona.personaId) {
                    console.warn('[bblog-ea-launch] no persona - logged in?');
                    return;
                }
                persona.allowRunGame = true;
                window.launcher.playablePersona[BF4] = persona;
                console.log('[bblog-ea-launch] join enabled for', persona.personaName);
            })
            .catch(function (e) { console.warn('[bblog-ea-launch]', e); });
    }

    seed();
    // Battlelog swaps pages over AJAX and rebuilds this cache, so keep at it.
    setInterval(seed, 3000);
})();
