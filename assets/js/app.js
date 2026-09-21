// SWARM change: the fonts of the Swarm Style Guide v2 are bundled from npm and
// emitted into priv/static by webpack, so the browser never requests anything
// from a third party. Upstream linked fonts.googleapis.com from the layout.
import "@fontsource/sora/400.css"
import "@fontsource/sora/600.css"
import "@fontsource/sora/700.css"
import "@fontsource/manrope/400.css"
import "@fontsource/manrope/500.css"
import "@fontsource/manrope/600.css"
import "@fontsource/jetbrains-mono/400.css"
import "@fontsource/jetbrains-mono/500.css"

import "../css/app.scss"

import "phoenix_html"
import 'alpinejs'
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

// SWARM change: the light/dark toggle and its localStorage entry are gone.
// The design system is one dark theme, and the explorer now stores nothing in
// the browser beyond the session cookie Phoenix needs.
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken } })
liveSocket.connect()
window.liveSocket = liveSocket
