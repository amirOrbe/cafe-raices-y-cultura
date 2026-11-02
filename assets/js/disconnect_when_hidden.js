// Closes the LiveView websocket once the tab has been hidden for a while.
//
// Fly only auto-stops a machine when it has no open connections left, so a
// forgotten tab keeps it running (and billing) for hours. When the tab comes
// back, the socket reconnects and LiveView remounts the view, so data arrives
// fresh and forms are recovered automatically.
//
// A screen that must stay connected while hidden (for example, one that plays
// a sound when an order arrives) adds `data-keep-connected` to any element.
//
// Same file in every Livecraft app: if you change it here, change the others.

const HIDDEN_MS = 5 * 60 * 1000

export function disconnectWhenHidden(liveSocket, hiddenMs = HIDDEN_MS) {
  let timer = null
  let disconnectedByUs = false

  const keepConnected = () => document.querySelector("[data-keep-connected]") !== null

  const disconnect = () => {
    timer = null
    if (document.visibilityState !== "hidden" || keepConnected()) return
    if (!liveSocket.isConnected()) return

    disconnectedByUs = true
    liveSocket.disconnect()
  }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      clearTimeout(timer)
      timer = setTimeout(disconnect, hiddenMs)
      return
    }

    clearTimeout(timer)
    timer = null
    if (disconnectedByUs) {
      disconnectedByUs = false
      liveSocket.connect()
    }
  })
}
