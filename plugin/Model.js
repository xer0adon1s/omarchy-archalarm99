// Formatting + parsing helpers for the ArchAlarm '99 panel.

function pad2(n) {
  return String(n).padStart(2, "0")
}

function formatClock(epochSeconds) {
  var t = Number(epochSeconds) || 0
  if (t <= 0) return "--:--:--"
  var d = new Date(t * 1000)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
}

function formatDuration(totalSeconds) {
  var s = Math.max(0, Math.floor(Number(totalSeconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  return pad2(h) + ":" + pad2(m) + ":" + pad2(sec)
}

function defaultStatus() {
  return {
    enabled: false,
    version: "1.5.2",
    mode: "stealth",
    knownSafe: "on",
    startedAt: 0,
    blockedTotal: 0,
    recentEvents: [],
    topOffenders: [],
    hostnames: {},
    bannedIps: [],
    trustedIps: [],
    listenPorts: [],
    connections: [],
    connectionCount: 0,
    lastEventAt: 0,
    lastEventText: "",
    uptimeSec: 0,
    threatLevel: 0,
    now: Date.now() / 1000
  }
}

// Best-effort hostname for an IP already resolved by the monitor daemon.
// Empty string if not yet resolved (or resolution failed/timed out).
function hostnameFor(status, ip) {
  if (!status || !status.hostnames) return ""
  return String(status.hostnames[ip] || "")
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    var base = defaultStatus()
    for (var key in base) {
      if (parsed[key] === undefined || parsed[key] === null) parsed[key] = base[key]
    }
    return parsed
  } catch (e) {
    return defaultStatus()
  }
}

function defaultUpdateInfo() {
  return {
    checking: false,
    updateAvailable: false,
    currentVersion: "",
    latestVersion: "",
    lastCheckAt: 0,
    error: ""
  }
}

function parseUpdateInfo(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultUpdateInfo()
  try {
    var parsed = JSON.parse(text)
    var base = defaultUpdateInfo()
    for (var key in base) {
      if (parsed[key] === undefined || parsed[key] === null) parsed[key] = base[key]
    }
    return parsed
  } catch (e) {
    return defaultUpdateInfo()
  }
}

function threatLabel(level) {
  if (level >= 2) return "ALERT"
  if (level >= 1) return "ELEVATED"
  return "CALM"
}

// Ten little bars for the meter. threatLevel 0 keeps a faint idle glow (2
// lit) rather than looking dead when nothing has happened yet.
function meterLitCount(level) {
  if (level >= 2) return 10
  if (level >= 1) return 6
  return 2
}

// Well-known ports, purely cosmetic — labels the "what's actually
// listening" breakdown so raw numbers read as services at a glance.
var COMMON_PORTS = {
  20: "FTP-DATA", 21: "FTP", 22: "SSH", 23: "TELNET", 25: "SMTP",
  53: "DNS", 67: "DHCP", 68: "DHCP", 80: "HTTP", 110: "POP3",
  123: "NTP", 143: "IMAP", 443: "HTTPS", 445: "SMB", 465: "SMTPS",
  546: "DHCPv6", 587: "SMTP", 631: "CUPS", 993: "IMAPS", 995: "POP3S",
  3000: "DEV", 3306: "MYSQL", 5000: "DEV", 5353: "MDNS", 5432: "POSTGRES",
  6379: "REDIS", 8000: "DEV", 8080: "HTTP-ALT", 8443: "HTTPS-ALT",
  22000: "SYNCTHING", 25565: "MINECRAFT"
}

function portLabel(port) {
  var name = COMMON_PORTS[port]
  return name ? (port + " " + name) : String(port)
}

// Named color palettes for the panel. "system" is handled separately in
// Panel.qml (it reads the live Omarchy theme via qs.Commons.Color); every
// other entry here is a fixed, self-contained look.
var THEMES = {
  archalarm: {
    label: "ArchAlarm (default)",
    bg: "#050b05", border: "#1f6b2e",
    calm: "#33ff66", elevated: "#ffcc33", alert: "#ff3344",
    off: "#5a5a5a", dim: "#66aa66", faint: "#336633"
  },
  amberCrt: {
    label: "Amber CRT",
    bg: "#140a00", border: "#6b4a1f",
    calm: "#ffb347", elevated: "#ffe066", alert: "#ff3b30",
    off: "#5a5a5a", dim: "#cc9955", faint: "#7a5522"
  },
  cyberRed: {
    label: "Cyber Red Alert",
    bg: "#0d0505", border: "#6b1f2a",
    calm: "#ff4d6d", elevated: "#ff9f43", alert: "#ffffff",
    off: "#5a5a5a", dim: "#cc6677", faint: "#7a3340"
  }
}

var THEME_ORDER = ["archalarm", "amberCrt", "cyberRed", "system"]

function themeLabel(name) {
  if (name === "system") return "Match System Theme"
  return (THEMES[name] || THEMES.archalarm).label
}

function themePalette(name) {
  return THEMES[name] || THEMES.archalarm
}
