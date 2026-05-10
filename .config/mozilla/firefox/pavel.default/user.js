// ** Theme Default Options ****************************************************
// userchrome.css usercontent.css activate
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Fill SVG Color
user_pref("svg.context-properties.content.enabled", true);

// Restore Compact Mode - 89 Above
user_pref("browser.compactmode.show", true);

// about:home Search Bar - 89 Above
user_pref("browser.newtabpage.activity-stream.improvesearch.handoffToAwesomebar", false);

// CSS's `:has()` selector #457 - 103 Above
user_pref("layout.css.has-selector.enabled", true);

// Browser Theme Based Scheme - Will be activate 95 Above
// user_pref("layout.css.prefers-color-scheme.content-override", 3);

// ** Theme Related Options ****************************************************
// == Theme Distribution Settings ==============================================
// The rows that are located continuously must be changed `true`/`false` explicitly because there is a collision.
// https://github.com/black7375/Firefox-UI-Fix/wiki/Options#important
user_pref("userChrome.tab.connect_to_window",          true); // Original, Photon
user_pref("userChrome.tab.color_like_toolbar",         true); // Original, Photon

user_pref("userChrome.tab.lepton_like_padding",       false); // Original
user_pref("userChrome.tab.photon_like_padding",        true); // Photon

user_pref("userChrome.tab.dynamic_separator",         false); // Original, Proton
user_pref("userChrome.tab.static_separator",           true); // Photon
user_pref("userChrome.tab.static_separator.selected_accent", false); // Just option
user_pref("userChrome.tab.bar_separator",             false); // Just option

user_pref("userChrome.tab.newtab_button_like_tab",    false); // Original
user_pref("userChrome.tab.newtab_button_smaller",      true); // Photon
user_pref("userChrome.tab.newtab_button_proton",      false); // Proton

user_pref("userChrome.icon.panel_full",               false); // Original, Proton
user_pref("userChrome.icon.panel_photon",              true); // Photon

// Original Only
user_pref("userChrome.tab.box_shadow",                false);
user_pref("userChrome.tab.bottom_rounded_corner",     false);

// Photon Only
user_pref("userChrome.tab.photon_like_contextline",    true);
user_pref("userChrome.rounding.square_tab",            true);

// == Theme Custom Settings ====================================================
// -- User Chrome --------------------------------------------------------------
user_pref("userChrome.theme.private",                       false);
user_pref("userChrome.theme.proton_color.dark_blue_accent", false);
user_pref("userChrome.theme.monospace",                     false);
user_pref("userChrome.theme.transparent.frame",             false);
user_pref("userChrome.theme.transparent.menu",              false);
user_pref("userChrome.theme.transparent.panel",             false);
user_pref("userChrome.theme.non_native_menu",               false); // only for linux

user_pref("userChrome.decoration.disable_panel_animate",    true);
user_pref("userChrome.decoration.disable_sidebar_animate",  true);
user_pref("userChrome.decoration.panel_button_separator",   false);
user_pref("userChrome.decoration.panel_arrow",              false);

// == Theme Default Settings ===================================================
// -- User Chrome --------------------------------------------------------------
user_pref("userChrome.compatibility.theme",       true);
user_pref("userChrome.compatibility.os",          true);

user_pref("userChrome.theme.built_in_contrast",   true);
user_pref("userChrome.theme.system_default",      true);
user_pref("userChrome.theme.proton_color",        true);
user_pref("userChrome.theme.proton_chrome",       true); // Need proton_color
user_pref("userChrome.theme.fully_color",         true); // Need proton_color
user_pref("userChrome.theme.fully_dark",          true); // Need proton_color

user_pref("userChrome.decoration.cursor",         false);
user_pref("userChrome.decoration.field_border",   false);
user_pref("userChrome.decoration.download_panel", false);
user_pref("userChrome.decoration.animate",        false);

user_pref("userChrome.padding.tabbar_width",      true);
user_pref("userChrome.padding.tabbar_height",     true);
user_pref("userChrome.padding.toolbar_button",    true);
user_pref("userChrome.padding.navbar_width",      true);
user_pref("userChrome.padding.urlbar",            true);
user_pref("userChrome.padding.bookmarkbar",       true);
user_pref("userChrome.padding.infobar",           true);
user_pref("userChrome.padding.menu",              true);
user_pref("userChrome.padding.bookmark_menu",     true);
user_pref("userChrome.padding.global_menubar",    true);
user_pref("userChrome.padding.panel",             true);
user_pref("userChrome.padding.popup_panel",       true);

user_pref("userChrome.tab.multi_selected",        true);
user_pref("userChrome.tab.unloaded",              true);
user_pref("userChrome.tab.letters_cleary",        true);
user_pref("userChrome.tab.close_button_at_hover", true);
user_pref("userChrome.tab.sound_hide_label",      true);
user_pref("userChrome.tab.sound_with_favicons",   true);
user_pref("userChrome.tab.pip",                   true);
user_pref("userChrome.tab.container",             true);
user_pref("userChrome.tab.crashed",               true);

user_pref("userChrome.fullscreen.overlap",        true);
user_pref("userChrome.fullscreen.show_bookmarkbar", true);



user_pref("userChrome.icon.library",              true);
user_pref("userChrome.icon.panel",                true);
user_pref("userChrome.icon.menu",                 true);
user_pref("userChrome.icon.context_menu",         true);
user_pref("userChrome.icon.global_menu",          true);
user_pref("userChrome.icon.global_menubar",       true);
user_pref("userChrome.icon.1-25px_stroke",        true);

// -- User Content -------------------------------------------------------------
user_pref("userContent.player.ui",             true);
user_pref("userContent.player.icon",           true);
user_pref("userContent.player.noaudio",        true);
user_pref("userContent.player.size",           true);
user_pref("userContent.player.click_to_play",  true);

user_pref("userChrome.urlView.focus_item_border", true);
user_pref("userContent.newTab.full_icon",      true);
user_pref("userContent.newTab.searchbar",      true);

user_pref("userContent.page.field_border",     false);
user_pref("userContent.page.illustration",     false);
user_pref("userContent.page.proton_color",     true);
user_pref("userContent.page.dark_mode",        true); // Need proton_color
user_pref("userContent.page.proton",           true); // Need proton_color


//user_pref("layout.frame_rate",                            144);
user_pref("media.ffmpeg.vaapi.enabled",                   true);
user_pref("media.hardware-video-decoding.force-enabled",  true);

user_pref("identity.fxaccounts.enabled", true);
user_pref("browser.download.autohideButton",        false);
user_pref("browser.tabs.tabMinWidth",               100);
user_pref("mousewheel.default.delta_multiplier_y",            100);
user_pref("userChrome.autohide.page_action",          true);
user_pref("userChrome.autohide.forward_button",       true);
user_pref("userChrome.centered.urlbar",               true);
user_pref("userChrome.tab.close_button_at_hover.with_selected", true);
user_pref("userChrome.tab.close_button_at_hover.always",        true);
user_pref("findbar.highlightAll",                         true);
user_pref("userChrome.hidden.urlbar_iconbox",               true);
user_pref("userChrome.urlView.always_show_page_actions",               true);
user_pref("userContent.player.animate",            false);
user_pref("userContent.newTab.animate",        false);
user_pref("full-screen-api.warning.timeout",      0);
//user_pref("userChrome.tab.bottom_rounded_corner",     true);
//user_pref("userChrome.rounding.square_tab",            false);

user_pref("browser.translations.enable", true);
user_pref("browser.translations.automaticallyPopup", false);
user_pref("browser.bookmarks.restore_default_bookmarks", false);
user_pref("browser.bookmarks.showMobileBookmarks", false);
user_pref("browser.contentblocking.category", "standard");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage", "chrome://browser/content/blanktab.html");
user_pref("browser.startup.page", 3);
user_pref("browser.uidensity", 1);
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("browser.bookmarks.openInTabClosesMenu", false);
user_pref("dom.forms.autocomplete.formautofill", true);
user_pref("browser.warnOnQuitShortcut", false);
user_pref("general.autoScroll", true);
user_pref("widget.gtk.overlay-scrollbars.enabled", false);
user_pref("browser.shell.checkDefaultBrowser",          false);
user_pref("browser.link.open_newwindow",                3);
user_pref("browser.tabs.loadInBackground",              true);
user_pref("browser.tabs.warnOnClose",                   false);
user_pref("browser.download.useDownloadDir",            true);
user_pref("browser.download.start_downloads_in_tmp_dir", true);
user_pref("browser.download.open_pdf_attachments_inline", true);
user_pref("permissions.default.desktop-notification", 1);
user_pref("permissions.default.shortcuts", 2);
user_pref("media.hardwaremediakeys.enabled", false);
user_pref("media.eme.enabled", true);


user_pref("browser.tabs.dragDrop.createGroup.enabled", false);
user_pref("browser.tabs.groups.smart.enabled", false);
user_pref("browser.tabs.groups.smart.userEnabled", false);
user_pref("browser.tabs.hoverPreview.enabled", false);
user_pref("browser.tabs.hoverPreview.showThumbnails", false);
user_pref("browser.tabs.inTitlebar", 0);
user_pref("browser.urlbar.suggest.bookmark", false);
user_pref("browser.urlbar.suggest.clipboard", false);
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.suggest.openpage", false);
user_pref("browser.urlbar.suggest.quickactions", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.suggest.topsites", false);
user_pref("browser.urlbar.suggest.calculator", false);
user_pref("browser.urlbar.trending.featureGate", false);
user_pref("browser.urlbar.clipboard.featureGate", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("browser.newtabpage.activity-stream.showSearch",                false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites",            false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories",  false);
user_pref("browser.newtabpage.activity-stream.showSponsored",             false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites",     false);
user_pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.highlights", false);


//annoyances
user_pref("browser.ai.control.default", "blocked");
user_pref("browser.ai.control.linkPreviewKeyPoints", "blocked");
user_pref("browser.ai.control.pdfjsAltText", "blocked");
user_pref("browser.ai.control.sidebarChatbot", "blocked");
user_pref("browser.ai.control.smartTabGroups", "blocked");
user_pref("browser.ai.control.smartWindow", "blocked");
user_pref("browser.ai.control.translations", "blocked");
user_pref("browser.ml.enable", false);
user_pref("browser.ml.chat.enabled", false);
user_pref("browser.ml.chat.page", false);
user_pref("browser.ml.chat.menu", false);
user_pref("browser.ml.linkPreview.enabled", false);
user_pref("browser.safebrowsing.downloads.remote.enabled", false);
user_pref("browser.safebrowsing.downloads.remote.block_potentially_unwanted", false);
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.preferences.moreFromMozilla", false);
user_pref("browser.download.manager.addToRecentDocs", false);
user_pref("extensions.ml.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("userContent.newTab.pocket_to_last", false);
user_pref("signon.firefoxRelay.feature", "disabled");
user_pref("signon.generation.enabled", false);
user_pref("nimbus.rollouts.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("accessibility.typeaheadfind.flashBar", 0);
user_pref("browser.uitour.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("screenshots.browser.component.enabled", false);
user_pref("media.videocontrols.picture-in-picture.enabled", false);
user_pref("media.videocontrols.picture-in-picture.video-toggle.enabled", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.visibility", "hide-sidebar");



//hard staff
user_pref("network.dns.disablePrefetch", true);
user_pref("network.dns.disablePrefetchFromHTTPS", true);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.usage.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("browser.places.speculativeConnect.enabled", false);
user_pref("network.prefetch-next", false);
user_pref("pdfjs.enableAltText", false);
user_pref("pdfjs.enableScripting", false);
user_pref("privacy.clearOnShutdown_v2.cache", false);
user_pref("privacy.clearOnShutdown_v2.cookiesAndStorage", false);
user_pref("privacy.clearOnShutdown_v2.formdata", true);
user_pref("privacy.userContext.enabled", false);
user_pref("privacy.userContext.ui.enabled", flase);
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);
user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
user_pref("browser.search.serpEventTelemetryCategorization.regionEnabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.coverage.opt-out", true);
user_pref("toolkit.coverage.opt-out", true);
user_pref("toolkit.coverage.endpoint.base", "");
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.send_pings", false);
user_pref("captivedetect.canonicalURL", "");
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);


//smoothfox
//user_pref("apz.overscroll.enabled", true);
//user_pref("general.smoothScroll", true);
//user_pref("general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS", 12);
//user_pref("general.smoothScroll.msdPhysics.enabled", true);
//user_pref("general.smoothScroll.msdPhysics.motionBeginSpringConstant", 600);
//user_pref("general.smoothScroll.msdPhysics.regularSpringConstant", 650);
//user_pref("general.smoothScroll.msdPhysics.slowdownMinDeltaMS", 25);
//user_pref("general.smoothScroll.msdPhysics.slowdownMinDeltaRatio", "2");
//user_pref("general.smoothScroll.msdPhysics.slowdownSpringConstant", 250);
//user_pref("general.smoothScroll.currentVelocityWeighting", "1");
//user_pref("general.smoothScroll.stopDecelerationWeighting", "1");



//fastfox
user_pref("nglayout.initialpaint.delay", 100);
user_pref("nglayout.initialpaint.delay_in_oopif", 100);
user_pref("gfx.content.skia-font-cache-size", 50);
user_pref("content.notify.ontimer", false);
user_pref("content.notify.interval", 700000);
user_pref("content.sink.enable_perf_mode", 2);
user_pref("content.sink.perf_parse_time", 700000);
user_pref("content.sink.pending_event_mode", 0);
user_pref("content.sink.event_probe_rate", 20);
user_pref("dom.timeout.defer_during_load", false);
user_pref("network.http.tailing.enabled", true);
user_pref("content.max.tokenizing.time", 2000000);
user_pref("content.interrupt.parsing", false);
user_pref("content.switch.threshold", 700000);
user_pref("browser.newtab.preload", false);

user_pref("widget.wayland.vsync.enabled", true);
user_pref("widget.wayland.opaque-region.enabled", true);
user_pref("widget.dmabuf.enabled", true);
user_pref("widget.dmabuf-webgl.enabled", true);

user_pref("gfx.webrender.all", true);
user_pref("dom.webgpu.enabled", true);
user_pref("gfx.canvas.accelerated", true);
user_pref("gfx.canvas.accelerated.cache-items", 65536);
user_pref("gfx.canvas.accelerated.cache-size", 4096);
user_pref("webgl.max-size", 16384);

user_pref("browser.sessionhistory.max_entries", 10);
user_pref("browser.sessionhistory.max_total_viewers", 10);
user_pref("browser.cache.memory.max_entry_size", 131072);
user_pref("browser.cache.memory.capacity", 4194304);
user_pref("browser.sessionstore.max_tabs_undo", 0);
user_pref("browser.cache.disk.smart_size.enabled", false);
user_pref("browser.cache.disk.capacity", 4194304);
user_pref("browser.cache.disk.metadata_memory_limit", 131072);
user_pref("network.http.rcwn.enabled", false);

//process tree
user_pref("browser.preferences.defaultPerformanceSettings.enabled", false);
user_pref("fission.autostart", false);
user_pref("fission.webContentIsolationStrategy", 0);
user_pref("dom.ipc.processCount", 6);
user_pref("dom.ipc.processCount.webIsolated", 1);
user_pref("dom.ipc.processPrelaunch.fission.number", 1);

user_pref("dom.ipc.forkserver.enable", false);
user_pref("layers.gpu-process.enabled", false);
user_pref("network.process.enabled", false);
user_pref("dom.ipc.keepProcessesAlive.privilegedabout", 0);
user_pref("dom.ipc.processPrelaunch.enabled", true);
//user_pref("browser.opaqueResponseBlocking", false);
//user_pref("browser.opaqueResponseBlocking.javascriptValidator", false);

