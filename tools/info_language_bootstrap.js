// Embedded in single-file app descriptions. Never writes device settings.
window.CubicInfoLanguage = (function () {
  function normalize(value) {
    var v = String(value || "").replace(/_/g, "-").toLowerCase();
    if (/^de(?:-|$)/.test(v)) return "de";
    if (/^ja(?:-|$)/.test(v)) return "ja";
    if (/^zh-(?:tw|hk|mo|hant)(?:-|$)/.test(v)) return "zh-TW";
    if (/^zh(?:-|$)/.test(v)) return "zh-CN";
    return "en";
  }
  var requested = "", stored = "", listeners = [];
  try { var q = new URLSearchParams(location.search); requested = q.get("lang") || q.get("language") || ""; } catch (_) {}
  try { stored = localStorage.getItem("cubic.mainpage.language") || ""; } catch (_) {}
  var current = normalize(requested || stored || navigator.language);
  function publish(value) { current = normalize(value); listeners.forEach(function (fn) { fn(current); }); }
  if (!requested) {
    fetch("/api/system/fs/file?path=%2Fsd%2Fapps%2Fsettings.json", {cache:"no-store"})
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (s) { if (s && (s.language || s.locale || s.lang)) publish(s.language || s.locale || s.lang); })
      .catch(function () {});
  }
  return { normalize:normalize, subscribe:function (fn) { listeners.push(fn); fn(current); } };
}());
