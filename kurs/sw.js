// Service Worker: Netz zuerst (Updates kommen sofort), offline aus dem Zwischenspeicher
const CACHE = "kurs-aee23e5d8a";
const FILES = ["./", "./index.html", "./manifest.webmanifest", "./icon-180.png", "./icon-192.png", "./icon-512.png"];
self.addEventListener("install", (e) => { e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES))); self.skipWaiting(); });
self.addEventListener("activate", (e) => {
  // alte App-Versionen löschen, den gespiegelten Stand für Mitteilungen ("kurs-data") behalten
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE && k !== "kurs-data").map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET" || new URL(e.request.url).origin !== location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then((r) => { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return r; })
      .catch(() => caches.match(e.request).then((r) => r || caches.match("./index.html")))
  );
});

// Mitteilungen: Der Zeitplan auf GitHub schickt nur die Art ("nachmittag", "abend", "test").
// Den Text baut der Service Worker hier aus dem Stand, den die App zuletzt gespiegelt hat.
const isoDay = (x) => x.getFullYear() + "-" + String(x.getMonth() + 1).padStart(2, "0") + "-" + String(x.getDate()).padStart(2, "0");
function compose(kind, d, now) {
  now = now || new Date();
  const t0 = isoDay(now), fresh = !!(d && Date.now() - (d.at || 0) < 3 * 864e5);
  const inFerien = (s) => !!(d && (d.ferien || []).some((f) => f[0] <= s && s <= f[1]));
  let next = null;
  for (let i = 1, x = new Date(now); i < 14; i++) { x.setDate(x.getDate() + 1); const w = x.getDay(), s = isoDay(x); if (w >= 1 && w <= 5 && !inFerien(s)) { next = s; break; } }
  const open = fresh ? d.tasks.filter((t) => !t.x && next && t.d <= next) : [];
  const fach = Array.from(new Set(open.map((t) => t.f).filter(Boolean))).slice(0, 3).join(", ");
  const exam = fresh ? d.tasks.find((t) => !t.x && (t.y === "Klausur" || t.y === "Test") && t.d > t0 && t.d <= next) : null;
  const n = open.length, nTxt = n + (n === 1 ? " Aufgabe" : " Aufgaben");
  if (kind === "test") return { title:"Kurs", body:"Mitteilungen funktionieren ✓" };
  if (kind === "abend") {
    if (exam) return { title:"Morgen: " + exam.y + (exam.f ? " " + exam.f : ""), body:(n > 1 ? "Außerdem noch " + (n - 1) + " offen. " : "") + "Früh schlafen hilft mehr als Nachtschicht." };
    if (!fresh) return { title:"Für morgen alles erledigt?", body:"Kurz reinschauen und abhaken." };
    if (!n) return { title:"Alles erledigt für morgen ✓", body:"Nichts mehr offen. Tasche packen, fertig." };
    return { title:"Noch " + nTxt + " für morgen", body:(fach ? fach + " · " : "") + "Erledigtes abhaken nicht vergessen." };
  }
  if (inFerien(t0)) return { title:"Ferien", body:"Heute nichts zu tun." };
  return { title:"Schule aus – was ist auf?", body:"Trag deine Hausaufgaben ein, solange du sie noch weißt." + (n ? " Für morgen offen: " + nTxt + (fach ? " (" + fach + ")" : "") + "." : "") };
}
self.addEventListener("push", (e) => {
  e.waitUntil((async () => {
    let kind = "nachmittag";
    try { const p = e.data ? e.data.json() : null; if (p && p.kind) kind = p.kind; } catch (x) {}
    let d = null;
    try { const r = await caches.match("state.json", { cacheName:"kurs-data" }); if (r) d = await r.json(); } catch (x) {}
    const m = compose(kind, d);
    await self.registration.showNotification(m.title, { body:m.body, icon:"icon-192.png", badge:"icon-192.png", tag:"kurs-" + kind, data:{ url:"./" } });
  })());
});
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  e.waitUntil(clients.matchAll({ type:"window", includeUncontrolled:true }).then((cs) => {
    for (const c of cs) { if ("focus" in c) return c.focus(); }
    return clients.openWindow("./");
  }));
});
