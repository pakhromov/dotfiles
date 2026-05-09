// Hardware-accelerated video decoding via VA-API (Linux)
user_pref("media.ffmpeg.vaapi.enabled",                   true);
user_pref("media.hardware-video-decoding.force-enabled",  true);
// Always show downloads button (don't autohide when no active downloads)
user_pref("browser.download.autohideButton",        false);
// Minimum tab width before tab bar starts scrolling (default: 76)
user_pref("browser.tabs.tabMinWidth",               150);
// Hide page action icons (star, reader view, etc.) until hover
user_pref("userChrome.autohide.page_action",          true);
// Center URL text when not focused
user_pref("userChrome.centered.urlbar",               true);
// Hide close button on active tab too — show only on hover, regardless of tab count
user_pref("userChrome.tab.close_button_at_hover.with_selected", true);
user_pref("userChrome.tab.close_button_at_hover.always",        true);

user_pref("userChrome.hidden.urlbar_iconbox",               true);

user_pref("userChrome.urlView.always_show_page_actions",               true);

//user_pref("userChrome.tab.bottom_rounded_corner",     true);
//user_pref("userChrome.rounding.square_tab",            false);

user_pref("userContent.player.animate",            false);

user_pref("browser.translations.enable", true);
user_pref("browser.translations.automaticallyPopup", false);
user_pref("accessibility.typeaheadfind.flashBar", 0);
user_pref("browser.ai.control.default", "blocked");
user_pref("browser.ai.control.linkPreviewKeyPoints", "blocked");
user_pref("browser.ai.control.pdfjsAltText", "blocked");
user_pref("browser.ai.control.sidebarChatbot", "blocked");
user_pref("browser.ai.control.smartTabGroups", "blocked");
user_pref("browser.ai.control.smartWindow", "blocked");
user_pref("browser.ai.control.translations", "blocked");
user_pref("browser.bookmarks.restore_default_bookmarks", false);
user_pref("browser.bookmarks.showMobileBookmarks", false);
user_pref("browser.contentblocking.category", "standard");
user_pref("browser.ml.enable", false);
user_pref("browser.ml.chat.enabled", false);
user_pref("browser.ml.chat.page", false);
user_pref("browser.ml.chat.menu", false);
user_pref("browser.ml.linkPreview.enabled", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.safebrowsing.downloads.remote.block_potentially_unwanted", false);
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.search.serpEventTelemetryCategorization.regionEnabled", false);
user_pref("browser.startup.homepage", "chrome://browser/content/blanktab.html");
user_pref("browser.startup.page", 3);
user_pref("browser.tabs.dragDrop.createGroup.enabled", false);
user_pref("browser.tabs.groups.smart.enabled", false);
user_pref("browser.tabs.groups.smart.userEnabled", false);
user_pref("browser.tabs.hoverPreview.showThumbnails", false);
user_pref("browser.tabs.inTitlebar", 0);
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("browser.uidensity", 1);
user_pref("browser.urlbar.suggest.bookmark", false);
user_pref("browser.urlbar.suggest.clipboard", false);
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.suggest.openpage", false);
user_pref("browser.urlbar.suggest.quickactions", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("extensions.ml.enabled", false);
user_pref("dom.forms.autocomplete.formautofill", true);
user_pref("browser.urlbar.suggest.topsites", false);
user_pref("browser.urlbar.trending.featureGate", false);
user_pref("browser.warnOnQuitShortcut", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.usage.uploadEnabled", false);
user_pref("media.eme.enabled", true);
user_pref("media.videocontrols.picture-in-picture.video-toggle.enabled", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.dns.disablePrefetchFromHTTPS", true);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("browser.places.speculativeConnect.enabled", false);
user_pref("network.prefetch-next", false);
user_pref("pdfjs.enableAltText", false);
user_pref("privacy.clearOnShutdown_v2.cache", false);
user_pref("privacy.clearOnShutdown_v2.cookiesAndStorage", false);
user_pref("privacy.clearOnShutdown_v2.formdata", true);
user_pref("privacy.userContext.enabled", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("signon.firefoxRelay.feature", "disabled");
user_pref("signon.generation.enabled", false);
user_pref("general.autoScroll", true);
user_pref("nimbus.rollouts.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("browser.newtabpage.activity-stream.showSearch",                false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites",            false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories",  false);
user_pref("browser.newtabpage.activity-stream.showSponsored",             false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites",     false);
user_pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.highlights", false);
user_pref("browser.shell.checkDefaultBrowser",          false);
user_pref("browser.link.open_newwindow",                3);
user_pref("browser.tabs.loadInBackground",              true);
user_pref("browser.tabs.insertRelatedAfterCurren",      false);
user_pref("browser.tabs.warnOnClose",                   false);
user_pref("browser.download.useDownloadDir",            true);
user_pref("permissions.default.desktop-notification", 1);
user_pref("media.hardwaremediakeys.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("browser.preferences.moreFromMozilla", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("permissions.default.shortcuts", 2);
user_pref("browser.download.open_pdf_attachments_inline", true);
user_pref("browser.download.manager.addToRecentDocs", false);
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);
user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
user_pref("browser.download.start_downloads_in_tmp_dir", true);

user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("browser.discovery.enabled", false);

user_pref("apz.overscroll.enabled", true);
user_pref("general.smoothScroll", true);
user_pref("general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS", 12);
user_pref("general.smoothScroll.msdPhysics.enabled", true);
user_pref("general.smoothScroll.msdPhysics.motionBeginSpringConstant", 600);
user_pref("general.smoothScroll.msdPhysics.regularSpringConstant", 650);
user_pref("general.smoothScroll.msdPhysics.slowdownMinDeltaMS", 25);
user_pref("general.smoothScroll.msdPhysics.slowdownMinDeltaRatio", "2");
user_pref("general.smoothScroll.msdPhysics.slowdownSpringConstant", 250);
user_pref("general.smoothScroll.currentVelocityWeighting", "1");
user_pref("general.smoothScroll.stopDecelerationWeighting", "1");
user_pref("mousewheel.default.delta_multiplier_y", 300); // 250-400; adjust this number to your liking

user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
user_pref("privacy.userContext.ui.enabled", flase);
user_pref("pdfjs.enableScripting", false);
user_pref("browser.safebrowsing.downloads.remote.enabled", false);
user_pref("browser.uitour.enabled", false);

user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
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
user_pref("datareporting.usage.uploadEnabled", false);

user_pref("captivedetect.canonicalURL", "");
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);


user_pref("nglayout.initialpaint.delay", 300); // DEFAULT 5
user_pref("nglayout.initialpaint.delay_in_oopif", 300); // DEFAULT 5
user_pref("gfx.content.skia-font-cache-size", 300); //300 mb default=5;
user_pref("content.notify.ontimer", true); // DEFAULT
user_pref("content.notify.interval", 700000);// (.70s); default=120000 (.12s)
user_pref("content.max.tokenizing.time", 2000000); // (2.00s);
user_pref("content.interrupt.parsing", false); // HIDDEN
user_pref("content.switch.threshold", 1300000);
user_pref("browser.newtab.preload", false);

user_pref("gfx.canvas.accelerated.cache-items", 65536);
user_pref("gfx.canvas.accelerated.cache-size", 4096);
user_pref("webgl.max-size", 16384);

user_pref("browser.preferences.defaultPerformanceSettings.enabled", false);
user_pref("fission.webContentIsolationStrategy", 0);
user_pref("dom.ipc.processCount", 12);
user_pref("dom.ipc.processCount.webIsolated", 1); // default=4;
user_pref("dom.ipc.processPrelaunch.fission.number", 1); // default=3;
