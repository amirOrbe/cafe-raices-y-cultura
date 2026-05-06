// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/crc"
import topbar from "../vendor/topbar"

// ---------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------

/**
 * CarouselAutoplay — pushes "carousel_next" event to the server every 5 seconds.
 * Pauses on hover / touch to avoid interrupting the user.
 */
const CarouselAutoplay = {
  mounted() {
    this.interval = null
    this.startAutoplay()

    this.el.addEventListener("mouseenter", () => this.stopAutoplay())
    this.el.addEventListener("mouseleave", () => this.startAutoplay())
    this.el.addEventListener("touchstart", () => this.stopAutoplay(), {passive: true})
    this.el.addEventListener("touchend", () => {
      clearTimeout(this._touchTimeout)
      this._touchTimeout = setTimeout(() => this.startAutoplay(), 3000)
    }, {passive: true})
  },
  destroyed() {
    this.stopAutoplay()
  },
  startAutoplay() {
    this.stopAutoplay()
    this.interval = setInterval(() => {
      this.pushEvent("carousel_next", {})
    }, 6000)
  },
  stopAutoplay() {
    if (this.interval) {
      clearInterval(this.interval)
      this.interval = null
    }
  }
}

/**
 * SoundNotifier — plays audio cues via Web Audio API when the server pushes
 * a "play_sound" event. No audio files required.
 *
 * Sound types:
 *   "new_order"  — two quick bell hits → cocina/barra cuando llega una comanda
 *   "item_ready" — three-note ascending chime → mesero cuando el platillo está listo
 */
const SoundNotifier = {
  mounted() {
    this._userInteracted = false

    // Track first user interaction so the AudioContext can be created unlocked
    const onInteract = () => { this._userInteracted = true }
    document.addEventListener("click",    onInteract, { passive: true })
    document.addEventListener("touchend", onInteract, { passive: true })

    this.handleEvent("play_sound", ({ type }) => {
      this._play(type)
    })
  },

  // Creates a short-lived AudioContext, plays the sound, then closes it
  // immediately so the browser never shows persistent media controls.
  _play(type) {
    try {
      const ctx  = new (window.AudioContext || window.webkitAudioContext)()
      const tones = type === "new_order"
        ? [{ freq: 880, t: 0, dur: 0.22 }, { freq: 880, t: 0.26, dur: 0.22 }]
        : [{ freq: 523.25, t: 0, dur: 0.20 }, { freq: 659.25, t: 0.14, dur: 0.20 }, { freq: 783.99, t: 0.28, dur: 0.38 }]

      const totalDuration = Math.max(...tones.map(n => n.t + n.dur))

      tones.forEach(({ freq, t, dur }) => {
        const osc  = ctx.createOscillator()
        const gain = ctx.createGain()
        osc.connect(gain)
        gain.connect(ctx.destination)
        osc.type = "sine"
        osc.frequency.value = freq
        gain.gain.setValueAtTime(0.28, ctx.currentTime + t)
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + dur)
        osc.start(ctx.currentTime + t)
        osc.stop(ctx.currentTime + t + dur + 0.05)
      })

      // Close the context once all tones have finished — no lingering session
      setTimeout(() => ctx.close(), (totalDuration + 0.15) * 1000)
    } catch (_e) {
      // AudioContext unavailable — silently ignore
    }
  }
}

/**
 * GeolocationClockIn — requests the device's GPS position and pushes it to
 * the LiveView so the server can verify the employee is near the café.
 *
 * Events pushed to the server:
 *   "location_requesting"     — {} (GPS query started, show loading state)
 *   "clock_in_with_location"  — { latitude, longitude }
 *   "location_denied"         — { reason: "permission_denied" | "unavailable" | "timeout" }
 */
const GeolocationClockIn = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault()
      this.requestLocation()
    })
  },

  requestLocation() {
    if (!navigator.geolocation) {
      this.pushEvent("location_denied", {reason: "unavailable"})
      return
    }

    // Notify server that we're waiting for GPS (show loading spinner)
    this.pushEvent("location_requesting", {})

    navigator.geolocation.getCurrentPosition(
      (position) => {
        this.pushEvent("clock_in_with_location", {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude
        })
      },
      (err) => {
        // GeolocationPositionError codes:
        //   1 = PERMISSION_DENIED  → user must change browser settings, can't retry
        //   2 = POSITION_UNAVAILABLE → GPS hardware issue, may retry
        //   3 = TIMEOUT            → took too long, may retry
        const reason = err.code === 1 ? "permission_denied"
                     : err.code === 2 ? "unavailable"
                     : "timeout"
        this.pushEvent("location_denied", {reason})
      },
      // Allow positions up to 60 s old so slow indoor GPS can still succeed
      {enableHighAccuracy: true, timeout: 12000, maximumAge: 60000}
    )
  }
}

/**
 * FloorMapEditor — enables drag-and-drop repositioning of table chips on the
 * admin floor-map canvas. On drop, pushes a "table_moved" event to the server
 * with { id, x_pct, y_pct } so the new position can be persisted.
 *
 * Usage: <div id="..." phx-hook="FloorMapEditor">
 *          <div data-table-id="1" style="left: 30%; top: 50%">...</div>
 *        </div>
 */
const FloorMapEditor = {
  mounted() {
    const container = this.el
    let dragging = null
    let startClientX = 0, startClientY = 0
    let origLeft = 0, origTop = 0
    let moved = false

    container.addEventListener('pointerdown', (e) => {
      // Let clicks on action buttons (edit, etc.) propagate normally
      if (e.target.closest('[data-no-drag]')) return
      const chip = e.target.closest('[data-table-id]')
      if (!chip || e.button !== 0) return
      e.preventDefault()

      dragging = chip
      moved = false
      startClientX = e.clientX
      startClientY = e.clientY
      origLeft = parseFloat(chip.style.left)
      origTop  = parseFloat(chip.style.top)

      chip.style.zIndex     = '50'
      chip.style.transition = 'none'
      container.setPointerCapture(e.pointerId)
    })

    container.addEventListener('pointermove', (e) => {
      if (!dragging) return
      const rect = container.getBoundingClientRect()
      const dx = (e.clientX - startClientX) / rect.width  * 100
      const dy = (e.clientY - startClientY) / rect.height * 100

      if (Math.abs(dx) > 0.3 || Math.abs(dy) > 0.3) moved = true

      dragging.style.left = clamp(origLeft + dx, 3, 97) + '%'
      dragging.style.top  = clamp(origTop  + dy, 3, 97) + '%'
    })

    container.addEventListener('pointerup', (e) => {
      if (!dragging) return
      if (moved) {
        this.pushEvent('table_moved', {
          id:    parseInt(dragging.dataset.tableId),
          x_pct: parseFloat(dragging.style.left),
          y_pct: parseFloat(dragging.style.top)
        })
      } else {
        // Short tap (no drag) — treat as click: open the edit modal
        const id = parseInt(dragging.dataset.tableId)
        this.pushEvent('edit_table', { id: id })
      }
      dragging.style.zIndex     = ''
      dragging.style.transition = ''
      dragging = null
    })

    function clamp(v, min, max) { return Math.min(max, Math.max(min, v)) }
  }
}

/**
 * DismissableTip — hides an onboarding tip panel and remembers the choice
 * in localStorage so it never shows again for this browser.
 *
 * Usage: <div phx-hook="DismissableTip" data-tip-id="cocina">
 *          ...content...
 *          <button data-dismiss-tip>Entendido</button>
 *        </div>
 */
const DismissableTip = {
  mounted() {
    const tipId = this.el.dataset.tipId
    const key   = `crc_tip_dismissed_${tipId}`

    // Already dismissed in a previous session — vanish immediately
    if (localStorage.getItem(key)) {
      this.el.style.display = "none"
      return
    }

    const btn = this.el.querySelector("[data-dismiss-tip]")
    if (btn) {
      btn.addEventListener("click", () => {
        localStorage.setItem(key, "1")
        this.el.style.transition = "opacity 0.25s"
        this.el.style.opacity    = "0"
        setTimeout(() => { this.el.style.display = "none" }, 280)
      })
    }
  }
}

// ---------------------------------------------------------------------------
// LiveSocket setup
// ---------------------------------------------------------------------------

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    CarouselAutoplay,
    DismissableTip,
    FloorMapEditor,
    GeolocationClockIn,
    SoundNotifier,
  },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#8b5e3c"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
