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
 *   "clock_in_with_location"  — { latitude, longitude }
 *   "location_denied"         — {} (user denied permission or unavailable)
 */
const GeolocationClockIn = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault()

      if (!navigator.geolocation) {
        this.pushEvent("location_denied", {reason: "unavailable"})
        return
      }

      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.pushEvent("clock_in_with_location", {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude
          })
        },
        (_err) => {
          this.pushEvent("location_denied", {reason: "denied"})
        },
        {enableHighAccuracy: true, timeout: 10000, maximumAge: 0}
      )
    })
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
