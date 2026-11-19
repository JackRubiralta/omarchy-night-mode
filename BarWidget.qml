import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Night mode: one click dims every screen to the same real brightness (cd/m²)
// and the keyboard backlight; a second click puts everything back. The work is
// done by bin/night-mode; this widget draws the moon, follows the state file and
// re-applies night mode when a monitor is plugged in or out.
//
// Looks and behaves like an always-shown Omarchy indicator (Do Not Disturb,
// Stay Awake): full strength when on, dimmed when off.
BarWidget {
  id: root
  moduleName: "io.github.jackrubiralta.night-mode"

  property bool on: false
  readonly property string script: String(Qt.resolvedUrl("bin/night-mode")).replace(/^file:\/\//, "")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/night-mode"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // The script writes state.json on every change, from the bar or from a
  // keybinding, so the moon follows without polling.
  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readState(text())
    onLoadFailed: root.on = false
  }

  function readState(raw) {
    try {
      var state = JSON.parse(String(raw || "{}"))
      root.on = state.on === true
    } catch (e) {
      root.on = false
    }
  }

  // The state file is replaced with a rename, which can drop the watch, so
  // read it again now and then as a backstop.
  Timer {
    interval: 15000; running: true; repeat: true
    onTriggered: stateFile.reload()
  }

  Process {
    id: proc
    property string pending: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t === "on" || t === "off") root.on = (t === "on")
        stateFile.reload()
      }
    }
    onRunningChanged: {
      if (!running && pending !== "") {
        var next = pending
        pending = ""
        root.run(next)
      }
    }
  }

  function run(command) {
    if (proc.running) {
      proc.pending = command
      return
    }
    proc.command = [root.script, command]
    proc.running = true
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function calibrate() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation",
      root.shellQuote(root.script) + " calibrate"])
  }

  // Monitors come and go with docks and cables: dim a new one when night mode
  // is on, and give an unplugged one its own brightness back when it returns.
  // DDC/CI needs a moment after a hotplug before it answers.
  Timer {
    id: syncTimer
    interval: 2500
    onTriggered: root.run("sync")
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "monitoradded" || name === "monitoraddedv2" || name === "monitorremoved" || name === "monitorremovedv2")
        syncTimer.restart()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A filled crescent with two stars (Material Design Icons "weather-night"
    // with the inner contour removed); icon.svg holds the same path.
    iconComponent: Component {
      Item {
        Shape {
          id: moon
          readonly property real s: button.iconSize / 880
          width: 880; height: 880
          x: (parent.width - button.iconSize) / 2
          y: (parent.height - button.iconSize) / 2
          transform: Scale { xScale: moon.s; yScale: moon.s }
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: button.foreground
            strokeColor: "transparent"
            fillRule: ShapePath.WindingFill
            PathSvg { path: "M697 131 592 213 629 340 519 264 410 340 447 213 342 131 475 127 519 2 564 127ZM842 420 773 471 799 555 728 506 656 555 682 471 613 420 699 418 728 336 756 418ZM748 625Q764 623 780.5 636.5Q797 650 802.0 669.0Q807 688 797 703Q776 734 752 756Q672 836 564.5 864.5Q457 893 349.5 864.5Q242 836 162.0 756.0Q82 676 54.5 568.5Q27 461 54.5 353.5Q82 246 162 166Q187 141 215 121Q231 111 250.0 117.0Q269 123 282.0 138.5Q295 154 293 172Q285 262 315.5 350.0Q346 438 413.0 505.0Q480 572 568.0 603.5Q656 635 748 625Z" }
          }
        }
      }
    }
    // Worded like Omarchy's own indicators: what a click will do.
    tooltipText: root.on ? strings.t("tooltip.restore", "Restore Brightness") : strings.t("tooltip.dim", "Dim Screens")
    dimmed: !root.on
    opacity: root.on ? 1 : 0.45
    useActiveColor: false
    keepSpace: true
    horizontalMargin: 5
    verticalPadding: 5
    fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
    fixedHeight: root.vertical ? Style.bar.statusSlot : -1
    onPressed: function(b) {
      if (b === Qt.RightButton) root.calibrate()
      else root.run("toggle")
    }
  }
}
