// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/nerves_desktop"
import topbar from "../vendor/topbar"
import { Terminal } from '../vendor/xterm/xterm.mjs'
import { FitAddon } from '../vendor/xterm/addon-fit.mjs'

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {
  LocalTime: {
    mounted() {
      this.updated()
    },
    updated() {
      const dt = new Date(this.el.getAttribute("datetime"))
      const options = { hour: '2-digit', minute: '2-digit', second: '2-digit' }
      this.el.textContent = dt.toLocaleTimeString(undefined, options)
    }
  },
  // The device table scrolls horizontally, so an absolutely positioned menu
  // would be clipped by its container. Position against the viewport instead.
  MenuPanel: {
    mounted() {
      this.position()
      this.reposition = () => this.position()
      window.addEventListener("resize", this.reposition)
      window.addEventListener("scroll", this.reposition, true)

      const first = this.el.querySelector("[role=menuitem]:not([disabled])")
      if (first) { first.focus() }
    },
    updated() { this.position() },
    destroyed() {
      window.removeEventListener("resize", this.reposition)
      window.removeEventListener("scroll", this.reposition, true)
    },
    position() {
      const trigger = document.getElementById(this.el.dataset.trigger)
      if (!trigger) { return }

      const anchor = trigger.getBoundingClientRect()
      const panel = this.el.getBoundingClientRect()
      const gap = 4

      const below = anchor.bottom + gap
      const flipped = below + panel.height > window.innerHeight
      const top = flipped ? anchor.top - panel.height - gap : below

      this.el.style.top = `${Math.max(gap * 2, top)}px`
      this.el.style.left = `${Math.max(gap * 2, anchor.right - panel.width)}px`
    }
  },
  TauriOpen: {
    mounted() {
      this.el.addEventListener("click", (e) => {
        e.preventDefault()
        const url = this.el.getAttribute("href")
        this.pushEvent("open_url", {url})
      })
    }
  },
  Xterm: {
    mounted() {
      this.term = new Terminal({
        cursorBlink: true,
        fontSize: 14,
        fontFamily: '"IBM Plex Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace',
        // Matches the --color-ink surface and Nerves blues in app.css.
        theme: {
          background: '#0f2a36',
          foreground: '#dfe9ed',
          cursor: '#42a7c6',
          cursorAccent: '#0f2a36',
          selectionBackground: '#33647e',
          black: '#0f2a36',
          red: '#e4707c',
          green: '#4fc79f',
          yellow: '#e0a458',
          blue: '#42a7c6',
          magenta: '#b491d9',
          cyan: '#6fd0dd',
          white: '#dfe9ed',
          brightBlack: '#587886',
          brightRed: '#f28d97',
          brightGreen: '#6fdcb7',
          brightYellow: '#f0bd77',
          brightBlue: '#6cc4dd',
          brightMagenta: '#c9aae8',
          brightCyan: '#8fe2ee',
          brightWhite: '#ffffff',
        }
      })

      this.fitAddon = new FitAddon()
      this.term.loadAddon(this.fitAddon)

      this.pushResize = (cols, rows) => {
        clearTimeout(this.resizeTimer)
        this.resizeTimer = setTimeout(() => this.pushEvent("resize", {cols, rows}), 100)
      }
      this.term.onResize(({cols, rows}) => this.pushResize(cols, rows))

      this.term.open(this.el)
      this.fitAddon.fit()
      this.pushResize(this.term.cols, this.term.rows)

      this.resizeObserver = new ResizeObserver(() => {
        this.fitAddon.fit()
      })
      this.resizeObserver.observe(this.el)
      
      this.handleEvent("print", ({data}) => {
        const binaryString = atob(data);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
        this.term.write(bytes)
      })

      this.handleEvent("clear", () => {
        this.term.clear()
        this.term.reset()
      })

      this.term.onData(data => {
        this.pushEvent("data", {data})
      })
    },
    destroyed() {
      clearTimeout(this.resizeTimer)
      if (this.resizeObserver) {
        this.resizeObserver.disconnect()
      }
      if (this.term) {
        this.term.dispose()
      }
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

window.addEventListener("phx:copy", (event) => {
  let text = event.detail.text
  if (text) {
    navigator.clipboard.writeText(text).then(() => {
      console.log("Copied to clipboard:", text)
    })
  }
})

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
    window.addEventListener("keyup", _e => keyDown = null)
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
