import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.spenceriam.ai-sub-monitor"
  ipcTarget: "io.github.spenceriam.ai-sub-monitor"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  property string tab: "usage"
  property bool cursorActive: false
  property int settingsFocusCount: 0
  property int formRev: 0
  property double nowMs: Date.now()
  property var drafts: ({})
  property var expandedIds: []
  property var hiddenIds: []
  property var planOrder: []
  property var cardHeights: ({})
  property string uiDensity: "comfy"
  property bool setupDone: false
  property bool wantUsageAfterStatus: false
  property bool fillerOpen: false
  property int fillerFront: 0
  property int fillerBack: 0
  property real fillerFrontOpacity: 1
  readonly property int fillerCount: 6
  readonly property int fillerRotateMs: 30 * 60 * 1000
  property bool layoutReady: false
  property string dragId: ""
  property real dragX: 0
  property real dragY: 0
  property real dragGrabX: 0
  property real dragGrabY: 0
  property int dragInsert: 0
  property string settingsPlan: ""
  property string testState: ""
  property string testMessage: ""
  property string notifyAddedId: ""
  property var notifyAlarm: ({})
  property var notifyProblem: ({})
  property bool notifyReady: false
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property int tileMoveMs: 380

  readonly property string density: uiDensity === "compact" ? "compact" : "comfy"
  readonly property int cardPad: density === "compact" ? Style.space(10) : Style.spacing.panelPadding
  readonly property int gridGap: density === "compact" ? Style.space(8) : Style.spacing.panelGap
  readonly property int sectionGap: density === "compact" ? Style.space(10) : Style.spacing.panelGap
  readonly property int donutSize: density === "compact" ? Style.space(64) : Style.space(88)
  readonly property int collapsedTileH: cardPad * 2 + donutSize + Style.space(8) * 2 + Style.font.body * 2 + Style.space(4)

  readonly property real heightCap: {
    var screenH = panel.screenH
    return Math.round(screenH > 0 ? screenH * 0.7 : Style.space(640))
  }
  readonly property real chromeH: (hero.implicitHeight || 0) + (tabSwitch.implicitHeight || 0) + root.sectionGap * 2
  readonly property real scrollBudget: Math.max(Style.space(96), heightCap - panel.verticalContentInset - chromeH)

  readonly property var keyFields: [
    { id: "kimi", label: "Kimi Code", provider: "Moonshot AI", hint: "Code Console key — not a Moonshot wallet key" },
    { id: "glm", label: "GLM Coding Plan", provider: "Z.ai", hint: "Z.ai coding-plan key. Raw Authorization header." },
    { id: "minimax", label: "MiniMax Token Plan", provider: "MiniMax", hint: "Subscription Key — not a PAYG sk-api- key" },
    { id: "ollama", label: "Ollama Cloud", provider: "Ollama", hint: "Key from ollama.com/settings/keys" },
    { id: "kilo", label: "Kilo Pass", provider: "Kilo", hint: "Gateway API key from the bottom of app.kilo.ai/profile — not a BYOK provider key" },
    { id: "commandcode", label: "Command Code", provider: "Command Code", hint: "Studio API key from commandcode.ai — same key as the CLI" }
  ]
  readonly property string requestPlanUrl: "https://github.com/spenceriam/ai-sub-monitor/issues/new?title=Request%20a%20plan&body=Plan%20name%3A%0AProvider%20%28and%20site%29%3A%0ADocs%20or%20pricing%20URL%3A%0A"

  readonly property bool alarming: {
    for (var i = 0; i < providers.length; i++) {
      var h = bindingWindow(providers[i].limits || [])
      if (h && h.percent >= 0.9) return true
    }
    return false
  }

  readonly property bool needsSetup: usage.keyStatusReady && !root.setupDone && root.configuredCount() === 0

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function setTab(name) {
    if (dragId !== "") cancelDrag()
    tab = name === "settings" ? "settings" : "usage"
    if (tab !== "settings") {
      settingsPlan = ""
      testState = ""
      testMessage = ""
    }
    if (panelFlick) panelFlick.contentY = 0
  }

  function tabForUsageRequest() {
    if (!usage.keyStatusReady || root.needsSetup) return "settings"
    return "usage"
  }

  function revealTab(name) {
    var dest
    if (name === "settings") {
      wantUsageAfterStatus = false
      dest = "settings"
    } else {
      if (!usage.keyStatusReady) wantUsageAfterStatus = true
      dest = root.tabForUsageRequest()
    }
    root.setTab(dest)
    if (!root.opened) root.open()
  }

  function activateTab(name) {
    var dest = name === "settings" ? "settings" : root.tabForUsageRequest()
    if (root.opened && root.tab === dest) {
      root.close()
      return
    }
    root.revealTab(name)
  }

  function markSetupDoneIfConfigured() {
    if (root.setupDone || root.configuredCount() === 0) return
    root.setupDone = true
    root.saveUi()
  }

  function applyPendingUsageTab() {
    if (!wantUsageAfterStatus || !opened || !usage.keyStatusReady) return
    wantUsageAfterStatus = false
    root.setTab(root.needsSetup ? "settings" : "usage")
  }

  function fieldById(id) {
    for (var i = 0; i < keyFields.length; i++) {
      if (keyFields[i].id === id) return keyFields[i]
    }
    return null
  }

  function openSettingsPlan(id) {
    settingsPlan = String(id || "")
    testState = ""
    testMessage = ""
    formRev++
    if (panelFlick) panelFlick.contentY = 0
  }

  function backToPlanList() {
    settingsPlan = ""
    testState = ""
    testMessage = ""
    formRev++
    if (panelFlick) panelFlick.contentY = 0
  }

  function refreshNow() { usage.refreshAll() }

  function bindingWindow(windows) {
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].unlimited) continue
      var pct = Number(windows[i].percent)
      if (!(pct >= 0)) continue
      if (!best || pct > Number(best.percent)) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || !w.resetsAt) return -1
    var ms = new Date(w.resetsAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    var code = String(currency || "USD")
    if (code === "USD") return "$" + amount.toFixed(2)
    if (code === "EUR") return "€" + amount.toFixed(2)
    if (code === "GBP") return "£" + amount.toFixed(2)
    return code + " " + amount.toFixed(2)
  }

  function configuredCount() {
    var n = 0
    for (var i = 0; i < keyFields.length; i++) {
      if (root.keySaved(keyFields[i].id)) n++
    }
    return n
  }

  function usageTabLabel() {
    var n = root.providers.length
    if (n === 1) return "Usage (1 plan)"
    return "Usage (" + n + " plans)"
  }

  function planHidden(id) {
    return !!(id && hiddenIds && hiddenIds.indexOf(id) >= 0)
  }

  function setPlanHidden(id, hide) {
    if (!id) return
    var next = []
    var found = false
    var i
    for (i = 0; i < hiddenIds.length; i++) {
      if (hiddenIds[i] === id) found = true
      else next.push(hiddenIds[i])
    }
    if (hide && !found) next.push(id)
    hiddenIds = next
    saveUi()
  }

  function togglePlanHidden(id) {
    setPlanHidden(id, !root.planHidden(id))
  }

  function planMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  function modelRows(p) {
    var list = p ? (p.models || []) : []
    var rows = []
    for (var i = 0; i < list.length; i++) {
      rows.push({ name: String(list[i].name || ""), total: Number(list[i].total || 0) })
    }
    rows.sort(function (a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function keySaved(id) {
    return !!(usage.keyStatus && usage.keyStatus[id])
  }

  function setDraft(id, text) {
    var next = {}
    for (var i = 0; i < keyFields.length; i++) {
      var kid = keyFields[i].id
      next[kid] = kid === id ? text : String(drafts[kid] || "")
    }
    drafts = next
  }

  function saveAndTest(id) {
    if (!id || testState === "testing") return
    var value = String(drafts[id] || "").trim()
    if (value === "" && !root.keySaved(id)) {
      testState = "fail"
      testMessage = "Paste a key first"
      return
    }
    testState = "testing"
    testMessage = "Checking key…"
    if (value !== "") {
      var updates = {}
      updates[id] = value
      var empty = {}
      for (var j = 0; j < keyFields.length; j++) empty[keyFields[j].id] = ""
      drafts = empty
      formRev++
      notifyAddedId = id
      usage.saveThenTest(updates, id)
      return
    }
    notifyAddedId = ""
    usage.testKey(id)
  }

  function clearKey(id) {
    var updates = {}
    updates[id] = ""
    usage.saveKeys(updates)
    setDraft(id, "")
    setPlanHidden(id, false)
    notifyAlarm = root.flagSet(notifyAlarm, id, false)
    notifyProblem = root.flagSet(notifyProblem, id, false)
    root.saveNotify()
  }

  function planLabel(id) {
    var field = root.fieldById(id)
    if (field && field.label) return String(field.label)
    return String((usage.providerNames && usage.providerNames[id]) || id)
  }

  function flagOn(map, id) {
    return !!(map && id && map[id])
  }

  function flagSet(map, id, on) {
    var next = {}
    var key
    for (key in (map || {})) {
      if (map[key]) next[key] = true
    }
    if (!id) return next
    if (on) next[id] = true
    else delete next[id]
    return next
  }

  function sendNotify(opts) {
    var headline = String((opts && opts.headline) || "AI Subs")
    var body = String((opts && opts.body) || "")
    var urgency = String((opts && opts.urgency) || "low")
    var appName = String((opts && opts.appName) || "")
    var cmd = [root.omarchyPath + "/bin/omarchy-notification-send", "-g", "󰞯", "-u", urgency]
    if (appName !== "") {
      cmd.push("--app-name", appName)
    }
    cmd.push(headline)
    if (body !== "") cmd.push(body)
    cmd.push("--exec", "omarchy-shell", "shell", "summon", root.moduleName, "{}")
    Quickshell.execDetached(cmd)
  }

  function openRequestPlan() {
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-launch-browser", root.requestPlanUrl])
  }

  function providerProblemText(p) {
    if (!p || p.ready) return ""
    var status = String(p.usageStatusText || "")
    if (status === "Fetching usage…") return ""
    var auth = String(p.authHelpText || "")
    if (auth !== "") return auth
    return status
  }

  function applyNotify(text) {
    try {
      var parsed = JSON.parse(String(text || "").trim() || "{}")
      if (parsed && typeof parsed === "object") {
        notifyAlarm = parsed.alarm && typeof parsed.alarm === "object" ? parsed.alarm : {}
        notifyProblem = parsed.problem && typeof parsed.problem === "object" ? parsed.problem : {}
      }
    } catch (e) {
      notifyAlarm = {}
      notifyProblem = {}
    }
    notifyReady = true
    root.scanUsageNotify()
  }

  function saveNotify() {
    notifyFile.setText(JSON.stringify({ alarm: notifyAlarm, problem: notifyProblem }) + "\n")
  }

  function scanUsageNotify() {
    if (!notifyReady) return
    var alarm = notifyAlarm
    var problem = notifyProblem
    var alarmChanged = false
    var problemChanged = false
    var seen = {}
    var list = providers
    var i
    var id
    var key
    for (i = 0; i < list.length; i++) {
      var p = list[i]
      id = String((p && p.providerId) || "")
      if (!id) continue
      seen[id] = true
      var name = String((p && p.providerName) || root.planLabel(id))
      var h = root.planHeadline(p)
      if (h && h.alarm) {
        if (!root.flagOn(alarm, id)) {
          alarm = root.flagSet(alarm, id, true)
          alarmChanged = true
          root.sendNotify({
            appName: "AI Subs",
            urgency: "critical",
            headline: name + " is at " + h.text,
            body: "Usage is 90% or higher."
          })
        }
      } else if (root.flagOn(alarm, id)) {
        alarm = root.flagSet(alarm, id, false)
        alarmChanged = true
      }
      var msg = root.providerProblemText(p)
      if (msg !== "") {
        if (!root.flagOn(problem, id)) {
          problem = root.flagSet(problem, id, true)
          problemChanged = true
          root.sendNotify({
            appName: "AI Subs",
            urgency: "normal",
            headline: name + " needs attention",
            body: msg
          })
        }
      } else if (p && p.ready && root.flagOn(problem, id)) {
        problem = root.flagSet(problem, id, false)
        problemChanged = true
      }
    }
    for (key in alarm) {
      if (seen[key]) continue
      alarm = root.flagSet(alarm, key, false)
      alarmChanged = true
    }
    for (key in problem) {
      if (seen[key]) continue
      problem = root.flagSet(problem, key, false)
      problemChanged = true
    }
    if (alarmChanged) notifyAlarm = alarm
    if (problemChanged) notifyProblem = problem
    if (alarmChanged || problemChanged) root.saveNotify()
  }

  function planHeadline(p) {
    var h = bindingWindow(p ? (p.limits || []) : [])
    if (h && h.percent >= 0)
      return { pct: Number(h.percent), text: Math.round(h.percent * 100) + "%", alarm: h.percent >= 0.9 }
    var windows = p ? (p.limits || []) : []
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].unlimited) return { pct: 0, text: "∞", alarm: false }
    }
    return { pct: 0, text: "—", alarm: false }
  }

  function parseExpanded(value) {
    var out = []
    var parts = []
    if (value && typeof value === "object" && value.length >= 0)
      parts = value
    else if (typeof value === "string" && value !== "")
      parts = value.split(",")
    for (var i = 0; i < parts.length; i++) {
      var id = String(parts[i] || "").trim()
      if (id !== "" && out.indexOf(id) < 0) out.push(id)
    }
    return out
  }

  function isExpanded(id) {
    return !!(id && expandedIds && expandedIds.indexOf(id) >= 0)
  }

  function haveIds() {
    var ids = []
    var list = providers
    for (var i = 0; i < list.length; i++) {
      var id = String(list[i].providerId || "")
      if (id !== "") ids.push(id)
    }
    return ids
  }

  function mergeOrder(have, order) {
    var out = []
    var src = order || []
    var i
    for (i = 0; i < src.length; i++) {
      var id = String(src[i] || "")
      if (id !== "" && have.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
    }
    for (i = 0; i < have.length; i++) {
      if (out.indexOf(have[i]) < 0) out.push(have[i])
    }
    return out
  }

  function orderedIds() {
    return mergeOrder(haveIds(), planOrder)
  }

  function moveId(ids, id, toIndex) {
    var next = []
    var i
    for (i = 0; i < ids.length; i++) {
      if (ids[i] !== id) next.push(ids[i])
    }
    var idx = Math.max(0, Math.min(Number(toIndex), next.length))
    next.splice(idx, 0, id)
    return next
  }

  function liveIds() {
    var ids = orderedIds()
    if (dragId === "") return ids
    return moveId(ids, dragId, dragInsert)
  }

  function setCardHeight(id, h) {
    if (!id) return
    var prev = Number(cardHeights[id] || 0)
    if (Math.round(prev) === Math.round(h)) return
    var next = {}
    for (var k in cardHeights) next[k] = cardHeights[k]
    next[id] = h
    cardHeights = next
  }

  function computeLayout(boardW) {
    var ids = liveIds()
    var n = ids.length
    var empty = { map: ({}), fillers: [], height: 0 }
    if (n === 0 || !(boardW > 0)) return empty
    var cols = n <= 1 ? 1 : 2
    var gap = gridGap
    var colW = cols === 1 ? boardW : (boardW - gap) / 2
    var cells = []
    var col = 0
    var i
    var span = 1
    if (cols === 1) {
      for (i = 0; i < n; i++) cells.push({ kind: "plan", id: ids[i], span: 1 })
    } else {
      for (i = 0; i < n; i++) {
        span = root.isExpanded(ids[i]) ? 2 : 1
        if (span === 2 && col === 1) {
          cells.push({ kind: "filler", id: "", span: 1 })
          col = 0
        }
        cells.push({ kind: "plan", id: ids[i], span: span })
        col = span === 2 ? 0 : (col + 1) % 2
      }
      if (col === 1) cells.push({ kind: "filler", id: "", span: 1 })
    }
    var map = ({})
    var fillers = []
    var x = 0
    var y = 0
    col = 0
    var rowH = 0
    var maxY = 0
    for (i = 0; i < cells.length; i++) {
      var cell = cells[i]
      span = cell.span
      if (span === 2 && col === 1) {
        y += rowH + gap
        col = 0
        rowH = 0
      }
      var w = (span === 2 || cols === 1) ? boardW : colW
      var h = root.collapsedTileH
      if (cell.kind === "plan" && root.isExpanded(cell.id)) {
        var ch = Number(cardHeights[cell.id] || 0)
        if (ch > h) h = ch
      }
      x = col * (colW + gap)
      var rect = { x: x, y: y, w: w, h: h }
      if (cell.kind === "plan") map[cell.id] = rect
      else fillers.push(rect)
      if (h > rowH) rowH = h
      col += (cols === 1 ? 1 : span)
      if (col >= cols) {
        maxY = y + rowH
        y += rowH + gap
        col = 0
        rowH = 0
      }
    }
    if (col > 0) maxY = y + rowH
    return { map: map, fillers: fillers, height: maxY }
  }

  readonly property var boardLayout: {
    var _w = planBoard.width
    var _o = planOrder
    var _e = expandedIds
    var _d = dragId
    var _i = dragInsert
    var _h = cardHeights
    var _p = providers
    var _g = gridGap
    var _c = collapsedTileH
    return root.computeLayout(_w)
  }

  function slotRect(id) {
    var lay = boardLayout
    if (lay && lay.map && lay.map[id]) return lay.map[id]
    return { x: 0, y: 0, w: 0, h: root.collapsedTileH }
  }

  function fillerRect(i) {
    var f = boardLayout.fillers
    if (f && i >= 0 && i < f.length) return f[i]
    return { x: 0, y: 0, w: 0, h: root.collapsedTileH }
  }

  function indexAtPoint(px, py) {
    var ids = liveIds()
    var map = boardLayout.map
    var i
    var s
    for (i = 0; i < ids.length; i++) {
      s = map[ids[i]]
      if (!s) continue
      var insetX = Math.min(24, s.w * 0.18)
      var insetY = Math.min(24, s.h * 0.18)
      if (px >= s.x + insetX && px <= s.x + s.w - insetX && py >= s.y + insetY && py <= s.y + s.h - insetY)
        return i
    }
    return dragInsert
  }

  function beginDrag(id, localX, localY) {
    if (!id || root.isExpanded(id) || haveIds().length < 2) return
    var ids = orderedIds()
    var idx = ids.indexOf(id)
    if (idx < 0) return
    var s = slotRect(id)
    dragGrabX = localX
    dragGrabY = localY
    dragX = s.x
    dragY = s.y
    dragInsert = idx
    dragId = id
    if (panelFlick) panelFlick.cancelFlick()
  }

  function updateDrag(boardX, boardY) {
    if (dragId === "") return
    dragX = boardX - dragGrabX
    dragY = boardY - dragGrabY
    var idx = indexAtPoint(boardX, boardY)
    if (idx !== dragInsert) dragInsert = idx
  }

  function endDrag() {
    if (dragId === "") return
    planOrder = liveIds()
    dragId = ""
    saveUi()
  }

  function cancelDrag() {
    dragId = ""
  }

  function applyUi(text) {
    try {
      var parsed = JSON.parse(String(text || "").trim() || "{}")
      if (!parsed || typeof parsed !== "object") return
      expandedIds = root.parseExpanded(parsed.expanded)
      planOrder = root.parseExpanded(parsed.order)
      if (parsed.density === "compact" || parsed.density === "Compact") uiDensity = "compact"
      else if (parsed.density === "comfy" || parsed.density === "Comfy") uiDensity = "comfy"
      if (parsed.setupDone === true) setupDone = true
      hiddenIds = root.parseExpanded(parsed.hidden)
    } catch (e) {
    }
  }

  function saveUi() {
    uiFile.setText(JSON.stringify({
      expanded: expandedIds,
      density: density,
      order: mergeOrder(haveIds(), planOrder),
      setupDone: setupDone,
      hidden: hiddenIds
    }) + "\n")
  }

  function toggleExpand(id) {
    if (!id) return
    var next = []
    var found = false
    for (var i = 0; i < expandedIds.length; i++) {
      if (expandedIds[i] === id) found = true
      else next.push(expandedIds[i])
    }
    if (!found) next.push(id)
    expandedIds = next
    saveUi()
  }

  function setDensity(name) {
    uiDensity = name === "compact" ? "compact" : "comfy"
    saveUi()
  }

  function fillerUrl(i) {
    var n = root.fillerCount
    var idx = ((Number(i) % n) + n) % n
    return Qt.resolvedUrl("assets/filler-" + idx + ".png")
  }

  function randomFillerIndex(except) {
    var n = root.fillerCount
    if (n <= 1) return 0
    var i = Math.floor(Math.random() * n)
    var guard = 0
    while (i === except && guard < 8) {
      i = Math.floor(Math.random() * n)
      guard++
    }
    return i
  }

  function snapFiller() {
    var i = randomFillerIndex(-1)
    fillerBack = i
    fillerFront = i
    fillerFrontOpacity = 1
  }

  function cycleFiller() {
    var next = randomFillerIndex(fillerFront)
    fillerBack = fillerFront
    fillerFrontOpacity = 0
    fillerFront = next
    Qt.callLater(function () { root.fillerFrontOpacity = 1 })
  }

  // Always in the bar so Settings is reachable with zero keys.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    settingsFocusCount = 0
    if (!opened) {
      root.fillerOpen = false
      root.wantUsageAfterStatus = false
      if (root.dragId !== "") root.cancelDrag()
      return
    }
    cursorActive = false
    nowMs = Date.now()
    root.layoutReady = false
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshKeyStatus()
    if (root.configuredCount() > 0) usage.refreshAll()
    Qt.callLater(function () {
      root.layoutReady = true
      keyCatcher.forceActiveFocus()
    })
  }

  Usage {
    id: usage
    settings: root.settings
    hiddenIds: root.hiddenIds
  }

  Connections {
    target: usage
    function onKeyStatusChanged() {
      root.markSetupDoneIfConfigured()
      root.applyPendingUsageTab()
    }
    function onKeyStatusReadyChanged() {
      root.markSetupDoneIfConfigured()
      root.applyPendingUsageTab()
    }
    function onTestFinished(ok, id, message) {
      root.testState = ok ? "ok" : "fail"
      root.testMessage = message
      if (ok && root.notifyAddedId === id) {
        root.sendNotify({
          urgency: "low",
          headline: root.planLabel(id) + " added",
          body: "Connected. Click to open usage."
        })
      }
      root.notifyAddedId = ""
    }
    function onDataRevisionChanged() { root.scanUsageNotify() }
  }

  Process {
    running: true
    command: ["mkdir", "-p", usage.stateDir]
  }

  FileView {
    id: uiFile
    path: usage.stateDir + "/ui.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyUi(text())
    onLoadFailed: {
      root.expandedIds = []
      root.planOrder = []
      root.uiDensity = "comfy"
    }
  }

  FileView {
    id: notifyFile
    path: usage.stateDir + "/notify.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyNotify(text())
    onLoadFailed: {
      root.notifyAlarm = ({})
      root.notifyProblem = ({})
      root.notifyReady = true
      root.scanUsageNotify()
    }
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    interval: root.fillerRotateMs
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.cycleFiller()
  }

  Component.onCompleted: root.snapFiller()

  Item {
    visible: false
    width: 0
    height: 0
    Repeater {
      model: root.fillerCount
      Image {
        required property int index
        source: root.fillerUrl(index)
        asynchronous: true
        cache: true
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.revealTab("usage") }
    function close(): void { root.close() }
    function show(): void { root.revealTab("usage") }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.revealTab(root.tab === "usage" ? "settings" : "usage"); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰞯"
    active: root.alarming
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) root.activateTab("settings")
      else if (buttonCode === Qt.MiddleButton) root.activateTab(root.tab === "usage" ? "settings" : "usage")
      else root.activateTab("usage")
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, root.heightCap)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsFocusCount > 0

      onMoveRequested: function (dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.setTab(dx > 0 ? "settings" : "usage")
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: {
        if (root.fillerOpen) {
          root.fillerOpen = false
          return
        }
        root.close()
      }
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "r" || t === "R") root.refreshNow()
        if (t === "s" || t === "S") root.setTab("settings")
        if (t === "u" || t === "U") root.setTab("usage")
      }

      Column {
        id: column
        width: parent.width
        spacing: root.sectionGap

        Column {
          id: hero
          width: parent.width
          spacing: Style.space(2)

          PanelHero {
            width: parent.width
            title: "AI Subs"
            meta: ""
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display
                Text {
                  anchors.centerIn: parent
                  text: button.text
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
          }

          Text {
            width: parent.width
            leftPadding: Style.font.display + Style.space(14)
            text: "Your configured AI subscriptions at a glance"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Row {
          id: tabSwitch
          width: parent.width
          spacing: Style.spacing.md

          Button {
            width: (tabSwitch.width - tabSwitch.spacing) / 2
            text: root.usageTabLabel()
            selected: root.tab === "usage"
            hasCursor: root.cursorActive && root.tab === "usage"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.setTab("usage")
          }

          Button {
            width: (tabSwitch.width - tabSwitch.spacing) / 2
            text: "Settings"
            selected: root.tab === "settings"
            hasCursor: root.cursorActive && root.tab === "settings"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.setTab("settings")
          }
        }

        Item {
          width: parent.width
          height: Math.min(scrollInner.implicitHeight, root.scrollBudget)

          Flickable {
            id: panelFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: scrollInner.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height && root.dragId === ""
            onContentHeightChanged: contentY = root.clamp(contentY, 0, Math.max(0, contentHeight - height))
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical: ScrollBar {
              id: vScroll
              policy: panelFlick.contentHeight > panelFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
              implicitWidth: Style.space(6)
              padding: 0
              minimumSize: 0.12
              contentItem: Rectangle {
                implicitWidth: Style.space(6)
                radius: Style.cornerRadius
                color: root.alpha(root.foreground, vScroll.pressed ? 0.5 : (vScroll.hovered ? 0.38 : 0.28))
                visible: vScroll.size < 1.0
              }
              background: Rectangle {
                implicitWidth: Style.space(6)
                color: root.track
                visible: vScroll.size < 1.0
              }
            }

            Column {
              id: scrollInner
              width: panelFlick.width - (panelFlick.contentHeight > panelFlick.height ? Style.space(10) : 0)
              spacing: root.sectionGap

              Column {
                visible: root.tab === "usage" && root.providers.length === 0
                width: parent.width
                spacing: root.sectionGap

                Text {
                  width: parent.width
                  text: root.configuredCount() > 0
                    ? "All plans are hidden.\nClick the eye in Settings to show a tile."
                    : "No plans yet.\nPick a service in Settings and paste its key."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }

                Button {
                  width: parent.width
                  text: "Open Settings"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.setTab("settings")
                }
              }

              Item {
                id: planBoard
                visible: root.tab === "usage" && root.providers.length > 0
                width: parent.width
                height: root.boardLayout.height
                implicitHeight: height

                Repeater {
                  model: root.providers.length
                  PlanCard {
                    required property int index
                    plan: root.providers[index] || null
                    stripe: {
                      var ids = root.liveIds()
                      var i = ids.indexOf(planId)
                      return i < 0 ? index : i
                    }
                  }
                }

                FillerCard {
                  id: filler0
                  visible: root.boardLayout.fillers.length > 0
                  x: root.fillerRect(0).x
                  y: root.fillerRect(0).y
                  width: root.fillerRect(0).w
                  height: root.fillerRect(0).h
                  z: 0
                  Behavior on x {
                    enabled: root.layoutReady
                    TileMove {}
                  }
                  Behavior on y {
                    enabled: root.layoutReady
                    TileMove {}
                  }
                  Behavior on width {
                    enabled: root.layoutReady
                    TileMove {}
                  }
                }

                FillerCard {
                  id: filler1
                  visible: root.boardLayout.fillers.length > 1
                  x: root.fillerRect(1).x
                  y: root.fillerRect(1).y
                  width: root.fillerRect(1).w
                  height: root.fillerRect(1).h
                  z: 0
                  Behavior on x {
                    enabled: root.layoutReady
                    TileMove {}
                  }
                  Behavior on y {
                    enabled: root.layoutReady
                    TileMove {}
                  }
                  Behavior on width {
                    enabled: root.layoutReady
                    TileMove {}
                  }
                }
              }

              Column {
                visible: root.tab === "settings"
                width: parent.width
                spacing: root.sectionGap

                Column {
                  visible: root.settingsPlan === ""
                  width: parent.width
                  spacing: root.sectionGap

                  Text {
                    width: parent.width
                    text: "Pick a plan, then paste its key. Saved plans: the eye hides the Usage tile without removing the key."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Repeater {
                    model: root.keyFields
                    PlanPick {
                      required property var modelData
                      width: scrollInner.width
                      field: modelData
                    }
                  }

                  Button {
                    width: parent.width
                    text: "Don't see your plan? Request it on GitHub"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    verticalPadding: Style.spacing.controlPaddingY
                    onClicked: root.openRequestPlan()
                  }

                  Column {
                    width: parent.width
                    spacing: Style.space(6)
                    Text {
                      width: parent.width
                      text: "Density. Comfy matches Omarchy panel padding (18) and gap (14)."
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      wrapMode: Text.WordWrap
                    }
                    Row {
                      width: parent.width
                      spacing: Style.spacing.md
                      Button {
                        width: (parent.width - parent.spacing) / 2
                        text: "Comfy"
                        selected: root.density === "comfy"
                        bordered: true
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        fontSize: Style.font.bodySmall
                        verticalPadding: Style.spacing.controlPaddingY
                        onClicked: root.setDensity("comfy")
                      }
                      Button {
                        width: (parent.width - parent.spacing) / 2
                        text: "Compact"
                        selected: root.density === "compact"
                        bordered: true
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        fontSize: Style.font.bodySmall
                        verticalPadding: Style.spacing.controlPaddingY
                        onClicked: root.setDensity("compact")
                      }
                    }
                  }
                }

                Column {
                  visible: root.settingsPlan !== ""
                  width: parent.width
                  spacing: root.sectionGap

                  Button {
                    width: parent.width
                    text: "All plans"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    verticalPadding: Style.spacing.controlPaddingY
                    onClicked: root.backToPlanList()
                  }

                  KeyRow {
                    width: parent.width
                    field: root.fieldById(root.settingsPlan)
                  }

                  Button {
                    width: parent.width
                    text: root.testState === "testing" ? "Checking key…" : "Save and test"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    verticalPadding: Style.spacing.controlPaddingY
                    onClicked: root.saveAndTest(root.settingsPlan)
                  }

                  Text {
                    visible: root.testMessage !== ""
                    width: parent.width
                    text: root.testMessage
                    color: root.testState === "fail" ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Button {
                    visible: root.testState === "ok"
                    width: parent.width
                    text: "View usage"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    onClicked: root.setTab("usage")
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.fillerOpen
        anchors.fill: parent
        z: 20
        color: Qt.rgba(0, 0, 0, 0.82)

        FillerArt {
          anchors.fill: parent
          anchors.margins: Style.spacing.popupPadding
          imageFill: Image.PreserveAspectFit
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.fillerOpen = false
        }
      }
    }
  }

  component Donut: Item {
    id: donut
    property real percent: 0
    property bool alarming: false
    property string label: ""
    width: root.donutSize
    height: root.donutSize

    function css(c) {
      return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a + ")"
    }

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2
        var cy = height / 2
        var outer = Math.min(width, height) / 2
        var thickness = outer * 0.24
        var r = outer - thickness / 2
        var start = -Math.PI / 2
        var used = root.clamp(donut.percent, 0, 1) * 2 * Math.PI
        ctx.lineWidth = thickness
        ctx.lineCap = "butt"
        ctx.beginPath()
        ctx.strokeStyle = donut.css(root.track)
        ctx.arc(cx, cy, r, start + used, start + Math.PI * 2)
        ctx.stroke()
        if (used > 0.004) {
          ctx.beginPath()
          ctx.strokeStyle = donut.css(donut.alarming ? root.urgent : root.foreground)
          ctx.arc(cx, cy, r, start, start + used)
          ctx.stroke()
        }
      }
    }

    Text {
      anchors.centerIn: parent
      text: donut.label
      color: donut.alarming ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    onPercentChanged: canvas.requestPaint()
    onAlarmingChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()
  }

  component TileMove: NumberAnimation {
    duration: root.tileMoveMs
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]
  }

  component FillerArt: Item {
    id: fillerArt
    property int imageFill: Image.PreserveAspectCrop
    clip: true

    Image {
      anchors.fill: parent
      source: root.fillerUrl(root.fillerBack)
      fillMode: fillerArt.imageFill
      asynchronous: true
      mipmap: true
      cache: true
      smooth: true
    }

    Image {
      anchors.fill: parent
      source: root.fillerUrl(root.fillerFront)
      fillMode: fillerArt.imageFill
      opacity: root.fillerFrontOpacity
      asynchronous: true
      mipmap: true
      cache: true
      smooth: true
      Behavior on opacity {
        NumberAnimation {
          duration: root.tileMoveMs
          easing.type: Easing.OutQuint
        }
      }
    }
  }

  component FillerCard: Rectangle {
    id: fillerCard
    implicitHeight: root.collapsedTileH
    clip: true
    color: root.alpha(root.foreground, 0.04)
    border.width: 1
    border.color: root.alpha(root.foreground, 0.4)
    radius: Style.cornerRadius

    FillerArt {
      anchors.fill: parent
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.fillerOpen = true
    }
  }

  component PlanCard: Rectangle {
    id: planCard
    property var plan: null
    property int stripe: 0
    property bool didDrag: false
    property real pressLocalX: 0
    property real pressLocalY: 0

    readonly property string planId: plan ? String(plan.providerId || "") : ""
    readonly property bool expanded: root.isExpanded(planId)
    readonly property var headline: root.planHeadline(plan)
    readonly property var slot: root.slotRect(planId)
    readonly property bool dragging: root.dragId === planId

    x: dragging ? root.dragX : slot.x
    y: dragging ? root.dragY : slot.y
    width: slot.w
    height: dragging ? root.collapsedTileH : slot.h
    z: dragging ? 20 : 1
    opacity: dragging ? 0.92 : 1.0

    implicitHeight: inner.implicitHeight + root.cardPad * 2
    clip: true
    color: expanded
      ? root.alpha(root.foreground, 0.18)
      : (dragging || tileMouse.containsMouse
        ? root.alpha(root.foreground, 0.14)
        : (stripe % 2 === 1 ? root.alpha(root.foreground, 0.08) : root.alpha(root.foreground, 0.04)))
    border.width: 1
    border.color: root.alpha(root.foreground, 0.4)
    radius: Style.cornerRadius

    Behavior on x {
      enabled: root.layoutReady && !planCard.dragging
      TileMove {}
    }
    Behavior on y {
      enabled: root.layoutReady && !planCard.dragging
      TileMove {}
    }
    Behavior on width {
      enabled: root.layoutReady && !planCard.dragging
      TileMove {}
    }
    Behavior on height {
      enabled: root.layoutReady && !planCard.dragging
      TileMove {}
    }

    onImplicitHeightChanged: {
      if (planCard.expanded) root.setCardHeight(planCard.planId, implicitHeight)
    }
    onExpandedChanged: {
      if (expanded) root.setCardHeight(planId, implicitHeight)
    }

    Item {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: root.cardPad
      implicitHeight: planCard.expanded ? openRow.implicitHeight : closedCol.implicitHeight

      Column {
        id: closedCol
        visible: !planCard.expanded
        width: parent.width
        spacing: Style.space(8)

        Donut {
          anchors.horizontalCenter: parent.horizontalCenter
          percent: Number(planCard.headline.pct || 0)
          alarming: !!planCard.headline.alarm
          label: String(planCard.headline.text || "")
        }

        Text {
          width: parent.width
          text: planCard.plan ? String(planCard.plan.providerName || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: root.planMeta(planCard.plan)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          font.letterSpacing: 1.2
          horizontalAlignment: Text.AlignHCenter
        }
      }

      Row {
        id: openRow
        visible: planCard.expanded
        width: parent.width
        spacing: root.sectionGap

        Donut {
          percent: Number(planCard.headline.pct || 0)
          alarming: !!planCard.headline.alarm
          label: String(planCard.headline.text || "")
        }

        Column {
          id: detailCol
          width: Math.max(1, openRow.width - root.donutSize - openRow.spacing)
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: planCard.plan ? String(planCard.plan.providerName || "") : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.planMeta(planCard.plan)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            font.letterSpacing: 1.2
          }

          Column {
            visible: !!(planCard.plan && planCard.plan.balance)
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: "Remaining credits"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                text: {
                  var b = planCard.plan ? planCard.plan.balance : null
                  return b ? root.formatMoney(b.remaining, b.currency) : ""
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          BorderSurface {
            visible: !!(planCard.plan && String(planCard.plan.usageStatusText || "") !== "")
            width: parent.width
            implicitHeight: planStatus.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: planStatus
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: planCard.plan ? String(planCard.plan.authHelpText || planCard.plan.usageStatusText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSectionHeader {
            visible: !!(planCard.plan && planCard.plan.limits && planCard.plan.limits.length > 0)
            text: "LIMITS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: planCard.plan ? (planCard.plan.limits || []) : []
            LimitRow {
              required property var modelData
              width: detailCol.width
              window: modelData
            }
          }

          PanelSectionHeader {
            visible: root.modelRows(planCard.plan).length > 0
            text: "REQUESTS BY MODEL"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.modelRows(planCard.plan)
            ModelRow {
              required property var modelData
              width: detailCol.width
              row: modelData
              share: {
                var rows = root.modelRows(planCard.plan)
                return modelData.total / Math.max(1, rows.length ? rows[0].total : 1)
              }
            }
          }
        }
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      z: 1
      hoverEnabled: true
      preventStealing: pressed && !planCard.expanded && root.providers.length >= 2
      cursorShape: planCard.dragging
        ? Qt.ClosedHandCursor
        : (planCard.expanded || root.providers.length < 2 ? Qt.PointingHandCursor : Qt.OpenHandCursor)

      Timer {
        id: holdTimer
        interval: 160
        repeat: false
        onTriggered: {
          if (!tileMouse.pressed) return
          if (planCard.expanded) return
          planCard.didDrag = true
          root.beginDrag(planCard.planId, planCard.pressLocalX, planCard.pressLocalY)
        }
      }

      onPressed: function (mouse) {
        planCard.didDrag = false
        planCard.pressLocalX = mouse.x
        planCard.pressLocalY = mouse.y
        if (!planCard.expanded && root.providers.length >= 2) holdTimer.start()
      }

      onPositionChanged: function (mouse) {
        if (planCard.dragging) {
          var p = mapToItem(planBoard, mouse.x, mouse.y)
          root.updateDrag(p.x, p.y)
          return
        }
        if (!pressed || planCard.expanded || !holdTimer.running) return
        var dx = mouse.x - planCard.pressLocalX
        var dy = mouse.y - planCard.pressLocalY
        if (dx * dx + dy * dy > 64) {
          holdTimer.stop()
          planCard.didDrag = true
          root.beginDrag(planCard.planId, planCard.pressLocalX, planCard.pressLocalY)
          var q = mapToItem(planBoard, mouse.x, mouse.y)
          root.updateDrag(q.x, q.y)
        }
      }

      onReleased: function (mouse) {
        holdTimer.stop()
        if (planCard.dragging) {
          root.endDrag()
          return
        }
        if (!planCard.didDrag) root.toggleExpand(planCard.planId)
      }

      onCanceled: {
        holdTimer.stop()
        if (planCard.dragging) root.cancelDrag()
      }
    }
  }

  component HideToggle: Item {
    id: eyeBtn
    property string planId: ""
    visible: root.keySaved(planId)
    width: Style.space(28)
    height: Style.space(28)
    implicitWidth: width
    implicitHeight: height

    readonly property bool hiding: root.planHidden(planId)

    Text {
      anchors.centerIn: parent
      text: eyeBtn.hiding ? "󰈉" : "󰈈"
      color: eyeMouse.containsMouse ? root.foreground : (eyeBtn.hiding ? root.dim : root.foreground)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: eyeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.togglePlanHidden(eyeBtn.planId)
    }
  }

  component PlanPick: Rectangle {
    id: planPick
    property var field: null
    readonly property string fieldId: field ? String(field.id) : ""
    implicitHeight: pickInner.implicitHeight + Style.space(12) * 2
    color: pickMouse.containsMouse ? root.alpha(root.foreground, 0.14) : root.alpha(root.foreground, 0.04)
    border.width: 1
    border.color: root.alpha(root.foreground, 0.4)
    radius: Style.cornerRadius

    MouseArea {
      id: pickMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openSettingsPlan(planPick.fieldId)
    }

    Item {
      id: pickInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      implicitHeight: Math.max(pickCopy.implicitHeight, pickActions.implicitHeight)

      Column {
        id: pickCopy
        anchors.left: parent.left
        anchors.right: pickActions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        opacity: root.keySaved(planPick.fieldId) && root.planHidden(planPick.fieldId) ? 0.55 : 1

        Text {
          id: pickLabel
          width: parent.width
          text: planPick.field ? String(planPick.field.label || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Text {
          id: pickProvider
          width: parent.width
          visible: planPick.field && String(planPick.field.provider || "") !== ""
          text: planPick.field ? String(planPick.field.provider || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: pickActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        z: 1

        HideToggle {
          planId: planPick.fieldId
        }

        Text {
          id: pickState
          text: root.keySaved(planPick.fieldId) ? "Saved" : "Not set"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  component KeyRow: Column {
    id: keyRow
    property var field: null
    spacing: Style.space(6)

    readonly property string fieldId: field ? String(field.id) : ""

    Item {
      width: parent.width
      implicitHeight: Math.max(keyLabel.implicitHeight, keyActions.implicitHeight)

      Text {
        id: keyLabel
        text: keyRow.field ? String(keyRow.field.label || "") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.left: parent.left
        anchors.right: keyActions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.WordWrap
      }

      Row {
        id: keyActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        HideToggle {
          planId: keyRow.fieldId
        }

        Text {
          id: keyState
          text: root.keySaved(keyRow.fieldId) ? "Saved" : "Not set"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    Text {
      visible: keyRow.field && String(keyRow.field.provider || "") !== ""
      width: parent.width
      text: keyRow.field ? String(keyRow.field.provider || "") : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      text: keyRow.field ? String(keyRow.field.hint || "") : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    TextField {
      id: keyInput
      width: parent.width
      password: true
      placeholderText: root.keySaved(keyRow.fieldId) ? "Leave blank to keep" : "Paste key"
      foreground: root.foreground
      font.family: root.fontFamily
      onTextEdited: root.setDraft(keyRow.fieldId, text)
      onActiveFocusChanged: {
        if (activeFocus) root.settingsFocusCount++
        else root.settingsFocusCount = Math.max(0, root.settingsFocusCount - 1)
      }

      Connections {
        target: root
        function onFormRevChanged() { keyInput.text = "" }
      }
    }

    Button {
      visible: root.keySaved(keyRow.fieldId)
      text: "Remove key"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: {
        keyInput.text = ""
        root.clearKey(keyRow.fieldId)
      }
    }
  }

  component LimitRow: Column {
    id: limitRow
    property var window: null
    readonly property bool unlimited: !!(window && window.unlimited)
    readonly property bool alarming: !unlimited && window && window.percent >= 0.9
    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        text: limitRow.window ? String(limitRow.window.title || "") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        text: limitRow.unlimited
          ? "Unlimited"
          : (limitRow.window && String(limitRow.window.valueLabel || "") !== ""
            ? String(limitRow.window.valueLabel)
            : (limitRow.window && limitRow.window.percent >= 0
              ? Math.round(limitRow.window.percent * 100) + "%"
              : "—"))
        color: limitRow.alarming ? root.urgent : (limitRow.unlimited ? root.dim : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.unlimited ? -1 : (limitRow.window ? Number(limitRow.window.percent) : -1)
      alarming: limitRow.alarming
    }

    Text {
      width: parent.width
      text: {
        if (limitRow.unlimited) return "Not metered on this tier"
        var remainingMs = root.resetMsFor(limitRow.window)
        var note = limitRow.window && String(limitRow.window.resetNote || "") !== ""
          ? String(limitRow.window.resetNote) : ""
        var money = !!(limitRow.window && String(limitRow.window.valueLabel || "") !== "")
        var head = remainingMs > 0
          ? (money ? "Refills in " : "Resets in ") + root.formatDuration(remainingMs)
          : ""
        if (head && note) return head + " · " + note
        if (head) return head
        if (!note) return ""
        if (note.indexOf("every") === 0 || note.indexOf("5 hours") >= 0 || note.indexOf("after") >= 0)
          return "Resets " + note
        return note
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground
      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }

  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0
    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)
      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelCount.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelCount
      text: modelRow.row ? String(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
