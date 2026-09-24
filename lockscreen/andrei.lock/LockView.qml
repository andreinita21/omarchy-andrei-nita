import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  readonly property color accent: "#9d4edd"
  // Same violet -> purple -> fuchsia gradient as the andrei-nita theme borders.
  readonly property var accentStops: ["#7c3aed", "#9d4edd", "#c026d3"]
  readonly property string accentGradient: "rgba(7c3aedff) rgba(9d4eddff) rgba(c026d3ff) 45deg"
  readonly property color accentDim: Qt.rgba(accent.r, accent.g, accent.b, 0.75)
  readonly property string asciiArt: [
    "   ▄████████ ███▄▄▄▄   ████████▄     ▄████████    ▄████████  ▄█       ███▄▄▄▄    ▄█      ███        ▄████████ ",
    "  ███    ███ ███▀▀▀██▄ ███   ▀███   ███    ███   ███    ███ ███       ███▀▀▀██▄ ███  ▀█████████▄   ███    ███ ",
    "  ███    ███ ███   ███ ███    ███   ███    ███   ███    █▀  ███▌      ███   ███ ███▌    ▀███▀▀██   ███    ███ ",
    "  ███    ███ ███   ███ ███    ███  ▄███▄▄▄▄██▀  ▄███▄▄▄     ███▌      ███   ███ ███▌     ███   ▀   ███    ███ ",
    "▀███████████ ███   ███ ███    ███ ▀▀███▀▀▀▀▀   ▀▀███▀▀▀     ███▌      ███   ███ ███▌     ███     ▀███████████ ",
    "  ███    ███ ███   ███ ███    ███ ▀███████████   ███    █▄  ███       ███   ███ ███      ███       ███    ███ ",
    "  ███    ███ ███   ███ ███   ▄███   ███    ███   ███    ███ ███       ███   ███ ███      ███       ███    ███ ",
    "  ███    █▀   ▀█   █▀  ████████▀    ███    ███   ██████████ █▀         ▀█   █▀  █▀      ▄████▀     ███    █▀  ",
    "                                    ███    ███                                                                "
  ].join("\n")
  readonly property var asciiLines: asciiArt.split("\n")
  readonly property int asciiColumns: asciiLines.reduce(function(n, l) { return Math.max(n, l.length) }, 0)
  // Art is drawn as block cells snapped to whole pixels (terminal-like 1:2.2
  // aspect) so adjacent glyphs never show anti-aliased seams. Shrinks to fit
  // within 90% of the screen width.
  readonly property int asciiCellWidth: Math.max(2, Math.min(12, Math.floor(width * 0.9 / Math.max(1, asciiColumns))))
  readonly property int asciiCellHeight: Math.round(asciiCellWidth * 2.2)

  readonly property string placeholderText: "Enter Password"
  readonly property int fieldWidth: 381
  readonly property int fieldHeight: 67
  readonly property int outlineThickness: 3
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "andrei-border", root.accentGradient, root.outlineThickness, "border-alpha")

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: "#000000"

    Item {
      id: asciiText
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: inputField.top
      anchors.bottomMargin: root.asciiCellHeight * 2
      width: root.asciiColumns * root.asciiCellWidth
      height: root.asciiLines.length * root.asciiCellHeight

      // logo.png is the exact render used for the andrei-nita wallpaper: the
      // 2090x378 art plus 200px of glow padding on every side.
      Image {
        readonly property real artScale: parent.width / 2090
        anchors.centerIn: parent
        width: 2490 * artScale
        height: 778 * artScale
        source: Qt.resolvedUrl("logo.png")
        fillMode: Image.Stretch
        smooth: true
        mipmap: true
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    BorderSurface {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      // Push the field down so art + field sit centered as one block.
      anchors.verticalCenterOffset: Math.round((asciiText.height + asciiText.anchors.bottomMargin) / 2)
      color: "#000000"
      borderSpec: root.inputBorderSpec
      radius: Style.cornerRadius
      clip: true

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.borderTop
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve
        anchors.bottomMargin: inputField.borderBottom
        anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: root.accent
        selectionColor: root.accentDim
        selectedTextColor: "#000000"
        font.family: Style.font.family
        font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: root.accent
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? root.accent : (root.failureMessage.length > 0 ? Color.lock.textError : root.accentDim)
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Fingerprint hint pinned inside the field's right edge when a sensor is
      // enrolled, so the user knows they can touch to unlock instead of typing.
      // Matches hyprlock, which draws its fingerprint icon in the same spot.
      Text {
        id: fingerprintIcon
        objectName: "fingerprintIndicator"
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: root.accentDim
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
