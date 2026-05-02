import { Application, Container, Graphics, Text } from "pixi.js"

const H_MARGIN = 26
const V_MARGIN = 22
const TOP_OVERLAY_GUTTER = 32
const BOTTOM_OVERLAY_GUTTER = 20
const BAND_GAP = 10
const MAX_PHASE_PARTICLES = 60

const textStyle = {
  fill: "#f8fafc",
  fontFamily: "Azeret Mono, IBM Plex Mono, Iosevka, ui-monospace, monospace",
  fontSize: 11,
  fontWeight: "600",
  letterSpacing: 0.9,
}

const subtextStyle = {
  fill: "#94a3b8",
  fontFamily: "Azeret Mono, IBM Plex Mono, Iosevka, ui-monospace, monospace",
  fontSize: 9,
  fontWeight: "500",
  letterSpacing: 0.6,
}

export const BiotopeScene = {
  async mounted() {
    this.snapshot = null
    this.phaseBounds = []
    this.animatedNodes = []
    this.eventQueue = []
    this.destroyed = false

    this.handleSnapshot = (payload) => this.applySnapshot(payload)
    this.handleEvent("biotope_snapshot", this.handleSnapshot)
    this.handleEvent("biotope_event", (payload) => this.applyBiotopeEvent(payload))

    try {
      await this.initApp()
      this.applySnapshot(this.readSnapshotFromDataset())
    } catch (error) {
      console.error("BiotopeScene init failed", error)
      this.el.classList.add("sim-scene-canvas--error")
      this.el.innerHTML = "<div class=\"sim-scene-fallback\">PixiJS scene failed to initialize.</div>"
    }
  },

  updated() {
    this.ensureCanvasMounted()
    this.applySnapshot(this.readSnapshotFromDataset())
  },

  destroyed() {
    this.destroyed = true

    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
      this.resizeObserver = null
    }

    if (this.canvasClickHandler && this.app?.canvas) {
      this.app.canvas.removeEventListener("pointerdown", this.canvasClickHandler)
    }

    if (this.app) {
      this.app.destroy({ removeView: false }, { children: true, texture: true, textureSource: true })
      this.app = null
    }
  },

  async initApp() {
    this.app = new Application()

    await this.app.init({
      antialias: true,
      backgroundAlpha: 0,
      autoDensity: true,
      resolution: Math.min(window.devicePixelRatio || 1, 2),
      resizeTo: this.el,
    })

    if (this.destroyed) {
      return
    }

    this.layers = {
      backdrop: new Container(),
      particles: new Container(),
      events: new Container(),
      labels: new Container(),
      overlay: new Container(),
    }

    this.app.stage.addChild(this.layers.backdrop)
    this.app.stage.addChild(this.layers.particles)
    this.app.stage.addChild(this.layers.events)
    this.app.stage.addChild(this.layers.labels)
    this.app.stage.addChild(this.layers.overlay)

    this.app.ticker.add(() => this.animate())

    this.ensureCanvasMounted()

    this.resizeObserver = new ResizeObserver(() => {
      this.resizeRenderer()
      this.draw()
    })

    this.resizeObserver.observe(this.el)

    this.canvasClickHandler = (event) => {
      const phase = this.findPhaseAt(event)

      if (phase) {
        this.pushEvent("select_phase", { phase: phase.name })
      }
    }

    this.app.canvas.addEventListener("pointerdown", this.canvasClickHandler)
    this.resizeRenderer()
  },

  resizeRenderer() {
    if (!this.app) return

    const width = Math.max(this.el.clientWidth, 320)
    const height = Math.max(this.el.clientHeight, 320)

    this.app.renderer.resize(width, height)
  },

  applySnapshot(snapshot) {
    if (!snapshot || !this.app) return

    this.ensureCanvasMounted()
    this.snapshot = snapshot
    this.draw()
  },

  applyBiotopeEvent(payload) {
    if (!payload || !this.phaseBounds.length) return

    this.eventQueue.push({
      type: payload.type,
      phase: payload.phase,
      tick: payload.tick,
      frame: 0,
      maxFrames: payload.type === "hgt_transfer" ? 20 : 30,
    })
  },

  ensureCanvasMounted() {
    if (!this.app?.canvas) return
    if (this.el.contains(this.app.canvas)) return

    this.el.innerHTML = ""
    this.el.appendChild(this.app.canvas)
    this.resizeRenderer()
  },

  readSnapshotFromDataset() {
    const raw = this.el.dataset.biotopeSnapshot

    if (!raw) return null

    try {
      return JSON.parse(raw)
    } catch (_error) {
      return null
    }
  },

  draw() {
    if (!this.snapshot || !this.app) return

    this.animatedNodes = []
    this.layers.backdrop.removeChildren()
    this.layers.particles.removeChildren()
    this.layers.labels.removeChildren()
    this.layers.overlay.removeChildren()

    const width = this.app.screen.width
    const height = this.app.screen.height
    const phases = this.snapshot.phases || []

    if (phases.length === 0) return

    this.drawBackground(width, height)
    this.phaseBounds = this.layoutPhases(phases, width, height)

    this.phaseBounds.forEach((phaseBound, index) => {
      this.drawPhaseBand(phaseBound, index)
      this.drawPhaseParticles(phaseBound, index)
      this.drawPhaseLabel(phaseBound)
    })

    this.drawOverlay(width, height)
  },

  drawBackground(width, height) {
    const bg = new Graphics()

    bg.roundRect(0, 0, width, height, 20).fill({ color: "#08111b", alpha: 0.96 })
    bg.roundRect(0, 0, width, height, 20).stroke({ color: "#334155", alpha: 0.65, width: 1.5 })

    for (let y = 28; y < height; y += 28) {
      bg.moveTo(0, y).lineTo(width, y).stroke({ color: "#0f172a", alpha: 0.28, width: 1 })
    }

    for (let x = 24; x < width; x += 36) {
      bg.moveTo(x, 0).lineTo(x, height).stroke({ color: "#102034", alpha: 0.16, width: 1 })
    }

    this.layers.backdrop.addChild(bg)
  },

  layoutPhases(phases, width, height) {
    const innerWidth = width - H_MARGIN * 2
    const topInset = V_MARGIN + TOP_OVERLAY_GUTTER
    const bottomInset = V_MARGIN + BOTTOM_OVERLAY_GUTTER
    const innerHeight =
      height - topInset - bottomInset - BAND_GAP * Math.max(phases.length - 1, 0)
    const weights = phases.map((phase) => Math.max(phase.totalAbundance || 0, 1))
    const totalWeight = weights.reduce((sum, value) => sum + value, 0)
    const minBandHeight = Math.min(72, innerHeight / Math.max(phases.length, 1))
    const extraHeight = Math.max(0, innerHeight - minBandHeight * phases.length)

    let cursorY = topInset

    return phases.map((phase, index) => {
      const weight = weights[index]
      const heightShare = minBandHeight + (extraHeight * weight) / totalWeight
      const bandHeight =
        index === phases.length - 1 ? height - bottomInset - cursorY : Math.max(52, heightShare)

      const band = {
        ...phase,
        x: H_MARGIN,
        y: cursorY,
        width: innerWidth,
        height: bandHeight,
        isSelected: phase.name === this.snapshot.selectedPhase,
      }

      cursorY += bandHeight + BAND_GAP

      return band
    })
  },

  drawPhaseBand(phaseBound) {
    const band = new Graphics()
    const alpha = phaseBound.isSelected ? 0.22 : 0.13
    const strokeAlpha = phaseBound.isSelected ? 0.9 : 0.45
    const strokeWidth = phaseBound.isSelected ? 2.8 : 1.2
    const radius = 18

    band.roundRect(phaseBound.x, phaseBound.y, phaseBound.width, phaseBound.height, radius)
    band.fill({ color: phaseBound.color, alpha })
    band.stroke({ color: phaseBound.color, alpha: strokeAlpha, width: strokeWidth })

    // Selected phase: 2px top highlight line
    if (phaseBound.isSelected) {
      const hl = new Graphics()
      hl.roundRect(phaseBound.x + 2, phaseBound.y, phaseBound.width - 4, 2, 1)
      hl.fill({ color: phaseBound.color, alpha: 0.9 })
      this.layers.backdrop.addChild(hl)
    }

    this.layers.backdrop.addChild(band)
  },

  drawPhaseParticles(phaseBound, phaseIndex) {
    const lineages = (this.snapshot.lineages || [])
      .filter((lineage) => (lineage.phaseAbundance?.[phaseBound.name] || 0) > 0)
      .sort((left, right) => (right.phaseAbundance?.[phaseBound.name] || 0) - (left.phaseAbundance?.[phaseBound.name] || 0))

    if (lineages.length === 0) return

    const totalInPhase = lineages.reduce(
      (sum, lineage) => sum + (lineage.phaseAbundance?.[phaseBound.name] || 0),
      0
    )
    const particleBudget = Math.max(
      18,
      Math.min(MAX_PHASE_PARTICLES, Math.round(20 + Math.sqrt(totalInPhase) * 2.5))
    )

    let used = 0

    lineages.forEach((lineage, lineageIndex) => {
      if (used >= particleBudget) return

      const abundance = lineage.phaseAbundance?.[phaseBound.name] || 0
      const fraction = totalInPhase > 0 ? abundance / totalInPhase : 0
      let particleCount = Math.round(fraction * particleBudget)

      if (particleCount === 0 && abundance > 0 && used < particleBudget * 0.75) {
        particleCount = 1
      }

      particleCount = Math.min(particleCount, particleBudget - used)
      used += particleCount

      for (let i = 0; i < particleCount; i += 1) {
        const seed = `${phaseBound.name}:${lineage.id}:${i}`
        const rng = mulberry32(hashString(seed))
        const x = phaseBound.x + 18 + rng() * Math.max(phaseBound.width - 36, 10)
        const y = phaseBound.y + 22 + rng() * Math.max(phaseBound.height - 44, 10)
        const baseRadius = 1.2 + fraction * 5.5 + rng() * 0.5

        const particle = new Graphics()
        particle.x = x
        particle.y = y

        // Cluster-based shape variation
        switch (lineage.cluster) {
          case "biofilm":
            // Rounded square
            particle.rect(-baseRadius * 0.8, -baseRadius * 0.8, baseRadius * 1.6, baseRadius * 1.6)
            break
          case "motile":
            // Elongated ellipse
            particle.ellipse(0, 0, baseRadius * 1.5, baseRadius * 0.6)
            break
          default:
            particle.circle(0, 0, baseRadius)
        }

        particle.fill({ color: lineage.color, alpha: 1 })
        particle.alpha = 0.86

        this.layers.particles.addChild(particle)
        this.animatedNodes.push({
          node: particle,
          baseAlpha: particle.alpha,
          speed: 0.75 + phaseIndex * 0.1 + rng() * 0.25,
          scaleAmp: 0.045,
        })
      }
    })
  },

  drawPhaseLabel(phaseBound) {
    const title = new Text({
      text: `${phaseBound.label.toUpperCase()} · N ${formatCompact(phaseBound.totalAbundance)}`,
      style: textStyle,
    })

    title.x = phaseBound.x + 14
    title.y = phaseBound.y + 10

    const temp = phaseBound.temperature != null ? `${phaseBound.temperature}°C` : "—"
    const ph = phaseBound.ph != null ? `pH ${phaseBound.ph}` : ""
    const dil = phaseBound.dilutionRate != null ? `D ${Math.round(phaseBound.dilutionRate * 100)}%/tick` : ""

    const detail = new Text({
      text: `T ${temp} · ${ph} · ${dil}`,
      style: subtextStyle,
    })

    detail.x = phaseBound.x + 14
    detail.y = phaseBound.y + 26

    this.layers.labels.addChild(title)
    this.layers.labels.addChild(detail)
  },

  drawOverlay(width) {
    const overlayText = new Text({
      text: `tick ${this.snapshot.tick}`,
      style: {
        ...subtextStyle,
        fill: "#64748b",
      },
    })

    overlayText.anchor.set(1, 0)
    overlayText.x = width - 18
    overlayText.y = 12

    this.layers.overlay.addChild(overlayText)
  },

  animate() {
    const time = performance.now() / 1000

    this.animatedNodes.forEach((entry, index) => {
      const wave = Math.sin(time * entry.speed + index * 0.8)
      const alpha = clamp(entry.baseAlpha + wave * 0.05, 0.05, 1)
      const scale = 1 + wave * entry.scaleAmp

      entry.node.alpha = alpha
      entry.node.scale.set(scale)
    })

    // Process event animations
    if (this.eventQueue.length > 0) {
      this.layers.events.removeChildren()
      this.eventQueue = this.eventQueue.filter((entry) => {
        this.drawEventAnimation(entry)
        entry.frame += 1
        return entry.frame < entry.maxFrames
      })
    }
  },

  drawEventAnimation(entry) {
    if (!this.phaseBounds.length) return

    const phaseBound = this.phaseBounds.find((pb) => pb.name === entry.phase) || this.phaseBounds[0]
    const progress = entry.frame / entry.maxFrames
    const rng = mulberry32(hashString(`${entry.phase}:${entry.tick}:${entry.frame}`))
    const cx = phaseBound.x + 20 + rng() * (phaseBound.width - 40)
    const cy = phaseBound.y + 15 + rng() * (phaseBound.height - 30)

    const g = new Graphics()

    if (entry.type === "lineage_born") {
      const radius = progress * 20
      const alpha = clamp(1 - progress * 1.2, 0, 1)
      g.circle(cx, cy, radius)
      g.stroke({ color: 0x4ade80, alpha, width: 1.5 })
    } else if (entry.type === "lineage_extinct") {
      const radius = clamp((1 - progress) * 16, 0, 16)
      const alpha = clamp(1 - progress * 1.5, 0, 1)
      g.circle(cx, cy, radius)
      g.stroke({ color: 0xf87171, alpha, width: 1.5 })
    } else if (entry.type === "hgt_transfer") {
      const rng2 = mulberry32(hashString(`${entry.phase}:${entry.tick}:end`))
      const ex = phaseBound.x + 20 + rng2() * (phaseBound.width - 40)
      const ey = phaseBound.y + 15 + rng2() * (phaseBound.height - 30)
      const alpha = clamp(1 - progress * 1.6, 0, 1)
      g.moveTo(cx, cy).lineTo(
        cx + (ex - cx) * progress,
        cy + (ey - cy) * progress
      )
      g.stroke({ color: 0xfb923c, alpha, width: 1 })
    }

    this.layers.events.addChild(g)
  },

  findPhaseAt(event) {
    if (!this.app) return null

    const rect = this.app.canvas.getBoundingClientRect()
    const x = event.clientX - rect.left
    const y = event.clientY - rect.top

    return this.phaseBounds.find((phaseBound) => {
      return (
        x >= phaseBound.x &&
        x <= phaseBound.x + phaseBound.width &&
        y >= phaseBound.y &&
        y <= phaseBound.y + phaseBound.height
      )
    })
  },
}

function hashString(value) {
  let hash = 2166136261

  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }

  return hash >>> 0
}

function mulberry32(seed) {
  let value = seed || 1

  return () => {
    value |= 0
    value = (value + 0x6d2b79f5) | 0
    let t = Math.imul(value ^ (value >>> 15), 1 | value)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function formatCompact(value) {
  if (value >= 1000000) {
    return `${(value / 1000000).toFixed(1)}M`
  }
  if (value >= 1000) {
    return `${(value / 1000).toFixed(1)}k`
  }
  return `${value}`
}
