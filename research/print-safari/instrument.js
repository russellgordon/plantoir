(function(){
  if (window.__p) return "already";
  const p = window.__p = {t0: performance.now(), ev: [], errors: []};
  const log = (e) => p.ev.push([e, Math.round(performance.now() - p.t0)]);
  p.log = log;
  window.addEventListener("error", (e) => p.errors.push(String(e.message)));
  window.addEventListener("unhandledrejection", (e) => p.errors.push("rej:" + String(e.reason)));
  const ow = console.warn; console.warn = function(...a){ log("warn:" + a.join(" ").slice(0,160)); return ow.apply(this,a) };
  const oe = console.error; console.error = function(...a){ log("error:" + a.join(" ").slice(0,160)); return oe.apply(this,a) };
  const hookFrame = (n) => {
    const w = n.contentWindow; if (!w || w.__hooked) return; w.__hooked = true;
    log("frame-added");
    const orig = w.print;
    w.print = function(){
      const imgs = n.contentDocument.querySelectorAll("img"); let pending = 0;
      for (const i of imgs) if (!i.complete) pending++;
      const path = n.contentDocument.documentElement.getAttribute("data-plantoir-print-path");
      log("print-called path=" + path + " imgs=" + imgs.length + " pending=" + pending + " activation=" + (navigator.userActivation ? navigator.userActivation.isActive : "n/a") + " ready=" + n.contentDocument.readyState + " fonts=" + n.contentDocument.fonts.status + " links=" + [...n.contentDocument.querySelectorAll("link[rel=stylesheet]")].filter(l=>!l.sheet).length + "/" + n.contentDocument.querySelectorAll("link[rel=stylesheet]").length);
      const r = orig.call(this); log("print-returned"); return r };
    w.addEventListener("beforeprint", () => log("frame-beforeprint"));
    w.addEventListener("afterprint", () => log("frame-afterprint"));
    if (window.__keepFrame) { n.remove = function(){ log("frame-remove-suppressed") } }
    w.addEventListener("error", (e) => p.errors.push("frame:" + String(e.message)));
  };
  new MutationObserver((ms) => { for (const m of ms) { for (const n of m.addedNodes) if (n.tagName === "IFRAME") hookFrame(n); for (const n of m.removedNodes) if (n.tagName === "IFRAME") log("frame-removed") } }).observe(document.body, {childList: true});
  // also catch synchronously: wrap appendChild on body
  const oa = document.body.appendChild; document.body.appendChild = function(n){ const r = oa.call(this, n); if (n && n.tagName === "IFRAME") hookFrame(n); return r };
  const st = document.querySelector(".plantoir-print-status");
  if (st) new MutationObserver(() => log("status=" + JSON.stringify(st.textContent))).observe(st, {childList: true, characterData: true, subtree: true});
  window.addEventListener("beforeprint", () => log("top-beforeprint"));
  window.addEventListener("afterprint", () => log("top-afterprint"));
  return "ok status=" + !!st;
})()
