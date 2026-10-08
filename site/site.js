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
