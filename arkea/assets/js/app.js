// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/arkea"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const hooks = {
  ...colocatedHooks,
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// ---------------------------------------------------------------------------
// Global keyboard shortcuts (Fase A.4)
//
// Vim-style two-key sequences for navigation: `g` then `d/w/s/c/a/h` to jump
// to Dashboard/World/Seed-Lab/Community/Audit/Help. `?` opens an in-page
// cheatsheet. SimLive-specific keys (`j/k/e/i/1..4`) dispatch a
// `phx:shortcut` window event that LiveViews can listen to with
// `phx-window-keydown`.
//
// We bypass shortcuts entirely when the user is typing in an input or
// editable region.
// ---------------------------------------------------------------------------
const NAV_KEYS = {
  d: "/dashboard",
  w: "/world",
  s: "/seed-lab",
  c: "/community",
  a: "/audit",
  h: "/help",
}

let pendingG = false
let gTimer = null

function isEditable(target) {
  if (!target) return false
  const tag = target.tagName
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true
  if (target.isContentEditable) return true
  return false
}

function showCheatsheet() {
  let dialog = document.getElementById("arkea-shortcuts-dialog")
  if (dialog) {
    dialog.remove()
    return
  }
  dialog = document.createElement("div")
  dialog.id = "arkea-shortcuts-dialog"
  dialog.className = "arkea-shortcuts-dialog"
  dialog.setAttribute("role", "dialog")
  dialog.setAttribute("aria-label", "Keyboard shortcuts")
  dialog.innerHTML = `
    <div class="arkea-shortcuts-dialog__panel">
      <div class="arkea-shortcuts-dialog__header">
        <span>Keyboard shortcuts</span>
        <button type="button" aria-label="Close" data-close>×</button>
      </div>
      <div class="arkea-shortcuts-dialog__body">
        <section>
          <h3>Navigation</h3>
          <dl>
            <dt><kbd>g</kbd> <kbd>d</kbd></dt><dd>Dashboard</dd>
            <dt><kbd>g</kbd> <kbd>w</kbd></dt><dd>World</dd>
            <dt><kbd>g</kbd> <kbd>s</kbd></dt><dd>Seed Lab</dd>
            <dt><kbd>g</kbd> <kbd>c</kbd></dt><dd>Community</dd>
            <dt><kbd>g</kbd> <kbd>a</kbd></dt><dd>Audit</dd>
            <dt><kbd>g</kbd> <kbd>h</kbd></dt><dd>Help</dd>
          </dl>
        </section>
        <section>
          <h3>Biotope viewport</h3>
          <dl>
            <dt><kbd>j</kbd> / <kbd>k</kbd></dt><dd>Next / previous lineage</dd>
            <dt><kbd>1</kbd>–<kbd>4</kbd></dt><dd>Switch bottom tab</dd>
            <dt><kbd>e</kbd></dt><dd>Open events tab</dd>
            <dt><kbd>i</kbd></dt><dd>Open interventions</dd>
          </dl>
        </section>
        <section>
          <h3>Global</h3>
          <dl>
            <dt><kbd>?</kbd></dt><dd>Toggle this cheatsheet</dd>
            <dt><kbd>Esc</kbd></dt><dd>Close drawers / dialogs</dd>
          </dl>
        </section>
      </div>
    </div>
  `
  dialog.addEventListener("click", e => {
    if (e.target === dialog || (e.target instanceof HTMLElement && e.target.dataset.close !== undefined)) {
      dialog.remove()
    }
  })
  document.body.appendChild(dialog)
}

window.addEventListener("keydown", e => {
  if (isEditable(e.target)) return
  if (e.metaKey || e.ctrlKey || e.altKey) return

  // `?` opens cheatsheet (with or without shift, depending on layout).
  if (e.key === "?" || (e.key === "/" && e.shiftKey)) {
    e.preventDefault()
    showCheatsheet()
    return
  }

  if (e.key === "Escape") {
    const dialog = document.getElementById("arkea-shortcuts-dialog")
    if (dialog) dialog.remove()
    return
  }

  // `g` then nav key.
  if (e.key === "g" && !pendingG) {
    pendingG = true
    if (gTimer) clearTimeout(gTimer)
    gTimer = setTimeout(() => { pendingG = false }, 1200)
    return
  }

  if (pendingG) {
    const dest = NAV_KEYS[e.key.toLowerCase()]
    pendingG = false
    if (gTimer) { clearTimeout(gTimer); gTimer = null }
    if (dest) {
      e.preventDefault()
      window.location.href = dest
      return
    }
  }

  // Single-key shortcuts dispatched as `phx:shortcut` for LiveViews to
  // pick up via `phx-window-keydown` or arbitrary JS handlers.
  if (["j", "k", "e", "i", "1", "2", "3", "4"].includes(e.key)) {
    window.dispatchEvent(new CustomEvent("phx:shortcut", {detail: {key: e.key}}))
  }
})

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
