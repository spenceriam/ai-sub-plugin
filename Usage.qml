import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property var settings: ({})
  property int dataRevision: 0
  property var providerIds: []
  property var records: []

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/ai-sub-monitor"
  readonly property string collectPath: decodeURIComponent(String(Qt.resolvedUrl("collect.py")).replace("file://", ""))
  readonly property var displayOrder: ["kimi", "glm", "minimax", "ollama", "kilo", "commandcode"]
  readonly property var providerNames: ({
    kimi: "Kimi Code",
    glm: "GLM Coding Plan",
    minimax: "MiniMax Token Plan",
    ollama: "Ollama Cloud",
    kilo: "Kilo Pass",
    commandcode: "Command Code"
  })

  property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 300)))
  property string pendingUpdateKind: ""
  property var retryIds: []
  property var hiddenIds: []

  readonly property var enabledProviders: {
    var rev = dataRevision
    var status = keyStatus
    var hidden = hiddenIds
    var byId = {}
    for (var i = 0; i < records.length; i++) {
      var rec = records[i] ? records[i].record : null
      if (!rec || !rec.id) continue
      byId[String(rec.id)] = rec
    }
    var result = []
    for (var j = 0; j < displayOrder.length; j++) {
      var id = displayOrder[j]
      if (!status || !status[id]) continue
      if (!providerVisible(id)) continue
      var existing = byId[id]
      if (existing && providerHasData(existing))
        result.push(displayProvider(existing))
      else
        result.push({
          providerId: id,
          providerName: String(providerNames[id] || id),
          chip: String(providerNames[id] || id),
          ready: false,
          usageStatusText: "Fetching usage…",
          authHelpText: "",
          limits: [],
          models: [],
          tierLabel: ""
        })
    }
    return result
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function providerVisible(id) {
    var list = hiddenIds || []
    var key = String(id || "")
    for (var i = 0; i < list.length; i++) {
      if (String(list[i]) === key) return false
    }
    return true
  }

  function providerHasData(rec) {
    return (rec.limits && rec.limits.length > 0)
      || String(rec.usageStatusText || "") !== ""
      || !!rec.balance
  }

  function displayProvider(rec) {
    return {
      providerId: String(rec.id),
      providerName: String(rec.name || rec.id),
      chip: String(rec.chip || rec.name || rec.id),
      ready: rec.ready === true,
      usageStatusText: String(rec.usageStatusText || ""),
      authHelpText: String(rec.authHelpText || ""),
      limits: Array.isArray(rec.limits) ? rec.limits : [],
      models: Array.isArray(rec.models) ? rec.models : [],
      tierLabel: String(rec.tierLabel || ""),
      balance: rec.balance && typeof rec.balance === "object" ? rec.balance : null
    }
  }

  Process {
    id: listProcess
    running: false
    command: ["find", root.stateDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyListing(text)
    }
  }

  function rescan() {
    if (!listProcess.running) listProcess.running = true
  }

  function applyListing(output) {
    var ids = []
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var name = lines[i].trim()
      if (name.slice(-5) === ".json") ids.push(name.slice(0, -5))
    }
    ids.sort()
    if (JSON.stringify(ids) !== JSON.stringify(providerIds)) providerIds = ids
  }

  Instantiator {
    id: watchers
    model: root.providerIds
    delegate: Record {
      required property var modelData
      providerId: modelData
      path: root.stateDir + "/" + modelData + ".json"
      onRecordChanged: root.bumpRevision()
    }
    onObjectAdded: (index, object) => root.rebuild()
    onObjectRemoved: (index, object) => root.rebuild()
  }

  function rebuild() {
    var result = []
    for (var i = 0; i < watchers.count; i++) {
      var item = watchers.objectAt(i)
      if (item) result.push(item)
    }
    records = result
    bumpRevision()
  }

  function bumpRevision() {
    dataRevision++
    scheduleRetry()
  }

  Timer {
    id: retryTimer
    interval: 30000
    repeat: false
    onTriggered: root.runUpdate(root.retryIds)
  }

  function scheduleRetry() {
    var advising = []
    for (var i = 0; i < records.length; i++) {
      var rec = records[i] ? records[i].record : null
      if (rec && rec.retryAdvised === true && providerVisible(String(rec.id || "")))
        advising.push(String(rec.id))
    }
    retryIds = advising
    if (advising.length > 0) retryTimer.restart()
    else retryTimer.stop()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runUpdate()
  }

  Process {
    id: updateProcess
    running: false
    onExited: {
      root.rescan()
      if (root.pendingUpdateKind !== "") {
        root.pendingUpdateKind = ""
        root.runUpdate()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("ai-sub-monitor", text.trim())
    }
  }

  function updateCommand(onlyIds) {
    var command = ["python3", root.collectPath]
    var hidden = hiddenIds || []
    for (var i = 0; i < hidden.length; i++) {
      if (hidden[i]) command.push("--except", String(hidden[i]))
    }
    if (onlyIds) {
      for (var i = 0; i < onlyIds.length; i++) command.push(onlyIds[i])
    }
    return command
  }

  function runUpdate(onlyIds) {
    if (updateProcess.running) {
      if (root.pendingUpdateKind === "") root.pendingUpdateKind = "queued"
      return
    }
    updateProcess.command = updateCommand(onlyIds)
    updateProcess.running = true
  }

  property var keyStatus: ({ kimi: false, glm: false, minimax: false, ollama: false, kilo: false, commandcode: false })
  property bool keyStatusReady: false
  property string savePayload: ""
  property string pendingTestId: ""
  property string testId: ""
  signal testFinished(bool ok, string id, string message)

  Process {
    id: statusProcess
    running: false
    command: ["python3", root.collectPath, "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyKeyStatus(text)
    }
  }

  Process {
    id: saveProcess
    running: false
    stdinEnabled: true
    command: ["python3", root.collectPath, "--save-keys"]
    onStarted: {
      write(root.savePayload + "\n")
      root.savePayload = ""
    }
    onExited: {
      root.refreshKeyStatus()
      if (root.pendingTestId !== "") {
        var id = root.pendingTestId
        root.pendingTestId = ""
        root.testKey(id)
      } else {
        root.refreshAll()
      }
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyKeyStatus(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("ai-sub-monitor", "save failed")
    }
  }

  function applyKeyStatus(text) {
    try {
      var parsed = JSON.parse(String(text || "").trim() || "{}")
      if (parsed && typeof parsed === "object") root.keyStatus = parsed
    } catch (e) {
    }
    root.keyStatusReady = true
  }

  function refreshKeyStatus() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function saveKeys(updates) {
    if (saveProcess.running) return
    root.savePayload = JSON.stringify(updates || {})
    saveProcess.running = true
  }

  function saveThenTest(updates, id) {
    root.pendingTestId = String(id || "")
    saveKeys(updates)
  }

  function testKey(id) {
    if (!id || testProcess.running) return
    root.testId = String(id)
    testProcess.running = true
  }

  function applyTestResult(text) {
    try {
      var parsed = JSON.parse(String(text || "").trim() || "{}")
      var ok = parsed && parsed.ok === true
      var id = parsed ? String(parsed.id || root.testId) : root.testId
      var message = parsed ? String(parsed.message || "") : ""
      if (message === "") message = ok ? "Connected" : "Could not read usage"
      root.testFinished(ok, id, message)
    } catch (e) {
      root.testFinished(false, root.testId, "Could not read usage")
    }
    root.rescan()
  }

  Process {
    id: testProcess
    running: false
    command: ["python3", root.collectPath, "--test", root.testId]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyTestResult(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("ai-sub-monitor", "test failed")
    }
  }

  function refreshAll() { runUpdate() }

  Component.onCompleted: {
    rescan()
    refreshKeyStatus()
  }
