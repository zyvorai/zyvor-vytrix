// Theme toggle, scroll-spy, the screenshot gallery, copy buttons. No dependencies.
(function () {
  var root = document.documentElement;
  var KEY = (window.__vytrixTheme || {}).key || "vytrix-site-theme";
  var btn = document.getElementById("theme");

  function paint(theme) {
    root.setAttribute("data-theme", theme);
    var m = document.querySelector('meta[name="theme-color"]');
    if (m) m.setAttribute("content", theme === "dark" ? "#07080d" : "#ffffff");
    if (btn) {
      btn.setAttribute("aria-pressed", theme === "dark" ? "true" : "false");
      btn.setAttribute("aria-label", theme === "dark" ? "Switch to light mode" : "Switch to dark mode");
    }
  }

  // ---- gallery: window style x appearance x view, all real screenshots
  var state = { style: "glass", mode: root.getAttribute("data-theme") === "light" ? "light" : "dark", view: "overview" };
  var LABEL = { glass: "Liquid Glass", macos27: "macOS 27", adwaita: "Adwaita", light: "light", dark: "dark", overview: "Overview", applications: "Applications", containers: "Containers", projects: "Projects", alerts: "Alerts" };
  var img = document.getElementById("shot"), cap = document.getElementById("shot-cap");
  var groups = [].slice.call(document.querySelectorAll(".seg"));

  function syncControls() {
    groups.forEach(function (g) {
      [].forEach.call(g.querySelectorAll('[role="radio"]'), function (b) {
        var on = b.getAttribute("data-value") === state[g.getAttribute("data-key")];
        b.setAttribute("aria-checked", on ? "true" : "false");
        b.tabIndex = on ? 0 : -1;
      });
    });
  }
  function render() {
    var src = "ux/" + state.style + "-" + state.mode + "-" + state.view + ".png";
    var text = LABEL[state.style] + " · " + LABEL[state.mode] + " · " + LABEL[state.view];
    var alt = "Vytrix " + LABEL[state.view] + " in the " + LABEL[state.style] + " window style, " + LABEL[state.mode];
    syncControls();
    if (!img || img.getAttribute("src") === src) { if (cap) cap.textContent = text; return; }
    img.classList.add("swap");
    var pre = new Image();
    pre.onload = pre.onerror = function () { img.src = src; img.alt = alt; img.classList.remove("swap"); };
    pre.src = src;
    if (cap) cap.textContent = text;
  }
  groups.forEach(function (g) {
    var radios = [].slice.call(g.querySelectorAll('[role="radio"]'));
    radios.forEach(function (b, i) {
      b.addEventListener("click", function () { state[g.getAttribute("data-key")] = b.getAttribute("data-value"); render(); });
      b.addEventListener("keydown", function (e) {
        var n = { ArrowRight: i + 1, ArrowDown: i + 1, ArrowLeft: i - 1, ArrowUp: i - 1, Home: 0, End: radios.length - 1 }[e.key];
        if (n === undefined) return;
        e.preventDefault();
        var t = radios[(n + radios.length) % radios.length];
        state[g.getAttribute("data-key")] = t.getAttribute("data-value"); render(); t.focus();
      });
    });
  });

  paint(root.getAttribute("data-theme") || "light");
  render();
  if (btn) btn.addEventListener("click", function () {
    var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    try { localStorage.setItem(KEY, next); } catch (e) { /* private mode */ }
    paint(next);
    state.mode = next; render(); // the gallery follows the page
  });

  // Scroll-spy
  var links = [].slice.call(document.querySelectorAll("#sections a"));
  if ("IntersectionObserver" in window && links.length) {
    var byId = {};
    links.forEach(function (a) { byId[a.getAttribute("href").slice(1)] = a; });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        links.forEach(function (a) { a.removeAttribute("aria-current"); });
        var a = byId[e.target.id]; if (a) a.setAttribute("aria-current", "true");
      });
    }, { rootMargin: "-40% 0px -55% 0px" });
    Object.keys(byId).forEach(function (id) { var s = document.getElementById(id); if (s) io.observe(s); });
  }

  // Copy buttons (clipboard API needs https/localhost; fall back so it also works elsewhere)
  var toast = document.getElementById("toast"), timer;
  function say(msg) { toast.textContent = msg; toast.hidden = false; clearTimeout(timer); timer = setTimeout(function () { toast.hidden = true; }, 2200); }
  function legacy(text) {
    var ta = document.createElement("textarea");
    ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta); ta.select();
    var ok = document.execCommand("copy"); document.body.removeChild(ta);
    if (!ok) throw new Error("copy refused");
  }
  [].forEach.call(document.querySelectorAll(".copy"), function (b) {
    b.addEventListener("click", function () {
      var text = b.parentNode.querySelector("pre").textContent;
      var done = function () { say("Copied to clipboard"); }, fail = function () { say("Copy failed. Select the text and copy it."); };
      if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done, function () { try { legacy(text); done(); } catch (e) { fail(); } });
      else { try { legacy(text); done(); } catch (e) { fail(); } }
    });
  });
})();

// Reveal on scroll, the pinned tour, and a little depth on the screenshots. No dependencies; content stays visible without JS or with reduced motion.
(function () {
  var root = document.documentElement;
  var reduce = window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches;
  var hasIO = "IntersectionObserver" in window;
  function mode() { return root.getAttribute("data-theme") === "light" ? "light" : "dark"; }

  // ---- reveal
  if (hasIO && !reduce) {
    var els = [].slice.call(document.querySelectorAll("main h2, main .sub, main .card, .band > div, .ticks li, .card-img, .frame, .code, .mac .device, .shot"))
      .filter(function (el) { return !el.closest(".step-img, .stage"); });
    var seen = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add("in"); seen.unobserve(e.target);
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
    els.forEach(function (el) {
      el.classList.add("reveal");
      var sib = el.parentNode && el.parentNode.children ? [].indexOf.call(el.parentNode.children, el) : 0;
      if (el.matches(".card, .band > div, .ticks li")) el.style.setProperty("--d", Math.min(sib, 5) * 70 + "ms");
      seen.observe(el);
    });
    // A fast flick can skip an element entirely, and the observer only fires on a change: reveal whatever is already behind the reader.
    var sweepTick = false;
    var sweep = function () {
      sweepTick = false;
      var edge = (window.innerHeight || 800) * 0.94;
      els.forEach(function (el) {
        if (!el.classList.contains("in") && el.getBoundingClientRect().top < edge) { el.classList.add("in"); seen.unobserve(el); }
      });
    };
    addEventListener("scroll", function () { if (!sweepTick) { sweepTick = true; requestAnimationFrame(sweep); } }, { passive: true });
  }

  // ---- the tour: steps scroll, one screenshot stays pinned
  var steps = [].slice.call(document.querySelectorAll("#steps .step"));
  var stage = document.getElementById("stage-img"), cap = document.getElementById("stage-cap");
  var cur = "overview";
  function glass(v) { return "ux/glass-" + mode() + "-" + v + ".png"; }
  function show(v, label) {
    cur = v;
    steps.forEach(function (s) {
      if (s.getAttribute("data-view") === v) s.setAttribute("aria-current", "true"); else s.removeAttribute("aria-current");
    });
    var src = glass(v);
    if (cap) cap.textContent = label + " · simulated telemetry";
    if (!stage || stage.getAttribute("src") === src) return;
    var pre = new Image();
    pre.onload = pre.onerror = function () { if (cur === v) { stage.src = src; stage.alt = "Vytrix " + label + " view on simulated telemetry"; } };
    pre.src = src;
  }
  if (steps.length && stage) {
    root.classList.add("tour-js");
    var label = function (s) { return s.getAttribute("data-label"); };
    if (hasIO) {
      var preloaded = false;
      var near = new IntersectionObserver(function (es) {
        if (!es[0].isIntersecting || preloaded) return;
        preloaded = true;
        steps.forEach(function (s) { new Image().src = glass(s.getAttribute("data-view")); });
      }, { rootMargin: "400px 0px" });
      near.observe(document.getElementById("tour"));
      var mid = new IntersectionObserver(function (es) {
        es.forEach(function (e) { if (e.isIntersecting) show(e.target.getAttribute("data-view"), label(e.target)); });
      }, { rootMargin: "-45% 0px -45% 0px" });
      steps.forEach(function (s) { mid.observe(s); });
    }
    steps.forEach(function (s) { s.addEventListener("focus", function () { show(s.getAttribute("data-view"), label(s)); }); });
  }

  // ---- screenshots follow the page theme (the gallery already does)
  function syncTheme() {
    var m = mode();
    [].forEach.call(document.querySelectorAll("img[data-view]"), function (i) { i.src = "ux/glass-" + m + "-" + i.getAttribute("data-view") + ".png"; });
    [].forEach.call(document.querySelectorAll("img[data-native]"), function (i) { i.src = "ux/native-" + m + "-" + i.getAttribute("data-native") + ".png"; });
    if (stage) { var s = steps.filter(function (x) { return x.getAttribute("data-view") === cur; })[0]; if (s) show(cur, label0(s)); }
  }
  function label0(s) { return s.getAttribute("data-label"); }
  syncTheme();
  if ("MutationObserver" in window) new MutationObserver(syncTheme).observe(root, { attributes: true, attributeFilter: ["data-theme"] });

  // ---- depth: the pinned and the wide screenshot settle into place as they arrive
  if (!reduce) {
    var depth = [].slice.call(document.querySelectorAll(".stage .device, .mac .device.wide")), ticking = false;
    var update = function () {
      ticking = false;
      var vh = window.innerHeight || 800;
      depth.forEach(function (el) {
        var p = Math.max(0, Math.min(1, (vh - el.getBoundingClientRect().top) / (vh * 0.75)));
        el.style.setProperty("--tilt", ((1 - p) * 7).toFixed(2) + "deg");
        el.style.setProperty("--sc", (0.95 + 0.05 * p).toFixed(3));
      });
    };
    var req = function () { if (!ticking) { ticking = true; requestAnimationFrame(update); } };
    addEventListener("scroll", req, { passive: true }); addEventListener("resize", req); update();
  }
})();
