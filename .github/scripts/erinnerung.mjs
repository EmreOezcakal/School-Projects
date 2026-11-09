// Schickt der App „Kurs“ einen Anstoß für eine Erinnerung.
// PUSH_CONFIG (GitHub-Secret) kommt aus der App: Einstellungen → Mitteilungen → Code.
// Inhalt: Push-Abo des iPads, eigenes Schlüsselpaar, Ferien. Aufgaben stehen NICHT drin.
// Test lokal ohne Senden: DRY=1 NOW=2026-11-10T13:40 node erinnerung.mjs
import webpush from "web-push";

// Erinnerungsplan in deutscher Zeit; passt zu den Schulschluss-Zeiten im Stundenplan
const PLAN = [
  { kind: "nachmittag", days: [1], at: "15:25" },
  { kind: "nachmittag", days: [2, 4], at: "13:35" },
  { kind: "nachmittag", days: [3, 5], at: "16:10" },
  { kind: "abend", days: [0, 1, 2, 3, 4], at: "19:30" },
];
const WINDOW = 60; // Minuten Verspätung, die GitHub haben darf

const raw = process.env.PUSH_CONFIG;
if (!raw) {
  console.log("Kein Secret PUSH_CONFIG – in der App Mitteilungen einschalten und den Code als Secret speichern.");
  process.exit(0);
}
let cfg;
try {
  cfg = JSON.parse(Buffer.from(raw.trim().replace(/^KURS-PUSH\./, ""), "base64").toString("utf8"));
} catch (e) {
  console.error("PUSH_CONFIG ist kein gültiger Code. Bitte in der App neu kopieren.");
  process.exit(1);
}

// Deutsche Uhrzeit (oder NOW zum Testen, als deutsche Uhrzeit gelesen)
function berlin() {
  if (process.env.NOW) {
    const [d, t] = process.env.NOW.split("T"), [y, m, day] = d.split("-").map(Number), [hh, mm] = t.split(":").map(Number);
    return { date: d, wd: new Date(Date.UTC(y, m - 1, day)).getUTCDay(), min: hh * 60 + mm, y, m, day };
  }
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Berlin", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .formatToParts(new Date()).map((x) => [x.type, x.value]));
  const y = +p.year, m = +p.month, day = +p.day;
  return { date: `${p.year}-${p.month}-${p.day}`, wd: new Date(Date.UTC(y, m - 1, day)).getUTCDay(), min: +p.hour * 60 + +p.minute, y, m, day };
}
const now = berlin();
const toMin = (s) => { const [h, m] = s.split(":").map(Number); return h * 60 + m; };
const tomorrow = new Date(Date.UTC(now.y, now.m - 1, now.day + 1)).toISOString().slice(0, 10);
const inFerien = (s) => (cfg.ferien || []).some(([a, b]) => a <= s && s <= b);

let kind = (process.env.KIND || "").trim();
if (!kind) {
  const due = PLAN.find((r) => r.days.includes(now.wd) && now.min - toMin(r.at) >= 0 && now.min - toMin(r.at) < WINDOW);
  if (!due) { console.log(`Nicht dran (${now.date}, ${Math.floor(now.min / 60)}:${String(now.min % 60).padStart(2, "0")} deutsche Zeit).`); process.exit(0); }
  kind = due.kind;
  if (kind === "nachmittag" && inFerien(now.date)) { console.log("Ferien – keine Erinnerung."); process.exit(0); }
  if (kind === "abend" && inFerien(tomorrow)) { console.log("Morgen Ferien – keine Erinnerung."); process.exit(0); }
}

if (process.env.DRY) { console.log(`Würde senden: ${kind}`); process.exit(0); }
try {
  webpush.setVapidDetails(cfg.subject, cfg.pub, cfg.priv);
  const r = await webpush.sendNotification(cfg.sub, JSON.stringify({ kind }), { TTL: 3600, urgency: "normal" });
  console.log(`Gesendet: ${kind} (Status ${r.statusCode})`);
} catch (e) {
  if (e.statusCode === 404 || e.statusCode === 410) console.error("Das Abo ist abgelaufen. In der App: Mitteilungen aus- und wieder einschalten, neuen Code als Secret speichern.");
  else console.error("Senden fehlgeschlagen:", e.statusCode || "", e.body || e.message);
  process.exit(1);
}
