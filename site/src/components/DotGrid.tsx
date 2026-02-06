"use client";

import { useEffect, useMemo, useRef, useState } from "react";

const DOT_SIZE = 5;
const DOT_GAP = 32;
const REVEAL_DURATION = 2.0; // seconds for wave to reach corners
const GREEN_FLASH_DURATION = 1.0; // seconds for initial green dot pulse

// Colors
const DOT_COLOR_SETTLED = [235, 235, 232] as const; // very light resting grey
const DOT_COLOR_WAVE = [215, 215, 212] as const; // subtle darker grey at wave peak
const GREEN_RGB = [34, 197, 94] as const;

// Trail settings
const GLOW_RADIUS = 140;
const TRAIL_DECAY = 0.97;
const TRAIL_THRESHOLD = 0.01;

type Dot = {
  x: number;
  y: number;
  delay: number;
  el: HTMLDivElement | null;
  glow: number;
  wave: number; // 0 = not yet revealed, 0→1 = wave arriving, 1 = settled
  revealed: boolean;
};

function rgbStr(r: number, g: number, b: number) {
  return `rgb(${Math.round(r)},${Math.round(g)},${Math.round(b)})`;
}

function lerp3(a: readonly [number, number, number], b: readonly [number, number, number], t: number): [number, number, number] {
  return [
    a[0] + (b[0] - a[0]) * t,
    a[1] + (b[1] - a[1]) * t,
    a[2] + (b[2] - a[2]) * t,
  ];
}

export function DotGrid({ onComplete, isDraggingRef }: { onComplete: () => void; isDraggingRef: React.RefObject<boolean> }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const dotsRef = useRef<Dot[]>([]);
  const mouseRef = useRef({ x: -9999, y: -9999 });
  const lastMoveRef = useRef(0);
  const rafRef = useRef<number>(0);
  const waveRafRef = useRef<number>(0);
  const [dimensions, setDimensions] = useState({ w: 0, h: 0 });
  const [mounted, setMounted] = useState(false);
  const isFinePointer = useRef(false);
  const revealDone = useRef(false);
  const onCompleteRef = useRef(onComplete);
  onCompleteRef.current = onComplete;

  useEffect(() => {
    const mq = window.matchMedia("(hover: hover) and (pointer: fine)");
    isFinePointer.current = mq.matches;
  }, []);

  useEffect(() => {
    const update = () => setDimensions({ w: window.innerWidth, h: window.innerHeight });
    update();
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);

  const dotData = useMemo(() => {
    if (dimensions.w === 0) return [];

    // Reset refs when grid recalculates
    dotsRef.current = [];

    const cols = Math.ceil(dimensions.w / DOT_GAP) + 1;
    const rows = Math.ceil(dimensions.h / DOT_GAP) + 1;
    const cx = dimensions.w / 2;
    const cy = dimensions.h / 2;
    const cornerDist = Math.hypot(cx, cy);

    const result: { x: number; y: number; delay: number }[] = [];
    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const x = col * DOT_GAP;
        const y = row * DOT_GAP;
        const dist = Math.hypot(x - cx, y - cy);
        const normalizedDist = dist / cornerDist;
        result.push({ x, y, delay: normalizedDist * REVEAL_DURATION });
      }
    }
    return result;
  }, [dimensions]);

  // Mount after first paint so we can animate
  // Use setTimeout instead of double-rAF so it fires even in background tabs
  useEffect(() => {
    if (dotData.length > 0 && !mounted) {
      const timer = setTimeout(() => setMounted(true), 50);
      return () => clearTimeout(timer);
    }
  }, [dotData, mounted]);

  // Full opening sequence: green dot flash → concentric wave → cards spring in early
  useEffect(() => {
    if (!mounted) return;

    const startTime = performance.now();
    const WAVE_WIDTH = 0.4;

    // Find the center-most dot (minimum delay = closest to center)
    const dots = dotsRef.current;
    let centerIdx = 0;
    for (let i = 1; i < dots.length; i++) {
      if (dots[i] && dots[i].delay < dots[centerIdx].delay) {
        centerIdx = i;
      }
    }

    const animate = (now: number) => {
      const elapsed = (now - startTime) / 1000;
      const dots = dotsRef.current;
      const centerDot = dots[centerIdx];

      // === Phase 1: Green dot flash (0 → GREEN_FLASH_DURATION) ===
      if (elapsed < GREEN_FLASH_DURATION) {
        if (centerDot?.el) {
          const t = elapsed / GREEN_FLASH_DURATION;
          // Two pulses via sin(4πt) clamped to positive half
          const pulse = Math.sin(t * Math.PI * 4);
          const intensity = Math.max(0, pulse);

          if (intensity > 0.01) {
            centerDot.el.style.opacity = String(intensity);
            centerDot.el.style.transform = `scale(${1 + intensity * 0.5})`;
            centerDot.el.style.backgroundColor = rgbStr(GREEN_RGB[0], GREEN_RGB[1], GREEN_RGB[2]);
          } else {
            centerDot.el.style.opacity = "0";
            centerDot.el.style.transform = "scale(0)";
          }
        }
        waveRafRef.current = requestAnimationFrame(animate);
        return;
      }

      // Reset center dot so wave can reveal it naturally
      if (centerDot?.el && !centerDot.revealed) {
        centerDot.el.style.opacity = "0";
        centerDot.el.style.transform = "scale(0)";
      }

      // === Phase 2: Concentric wave ===
      const waveElapsed = elapsed - GREEN_FLASH_DURATION;
      let allSettled = true;

      for (let i = 0; i < dots.length; i++) {
        const dot = dots[i];
        if (!dot.el) continue;

        const waveProgress = (waveElapsed - dot.delay) / WAVE_WIDTH;

        if (waveProgress < 0) {
          allSettled = false;
          continue;
        }

        if (!dot.revealed) {
          dot.revealed = true;
          dot.el.style.opacity = "1";
          dot.el.style.transform = "scale(1)";
        }

        if (waveProgress < 1) {
          const waveCurve = Math.sin(waveProgress * Math.PI);
          const color = lerp3(DOT_COLOR_SETTLED, DOT_COLOR_WAVE, waveCurve);
          const scale = 1 + waveCurve * 0.3;
          dot.el.style.backgroundColor = rgbStr(color[0], color[1], color[2]);
          dot.el.style.transform = `scale(${scale})`;
          dot.wave = waveProgress;
          allSettled = false;
        } else if (dot.wave < 1) {
          dot.wave = 1;
          dot.el.style.backgroundColor = rgbStr(DOT_COLOR_SETTLED[0], DOT_COLOR_SETTLED[1], DOT_COLOR_SETTLED[2]);
          dot.el.style.transform = "scale(1)";
        }
      }

      // Cards spring in at 70% of wave — before it reaches the corners
      if (waveElapsed >= REVEAL_DURATION * 0.7 && !revealDone.current) {
        revealDone.current = true;
        onCompleteRef.current();
      }

      if (!allSettled) {
        waveRafRef.current = requestAnimationFrame(animate);
      }
    };

    waveRafRef.current = requestAnimationFrame(animate);

    // If the tab was hidden during animation, skip to settled state when it becomes visible
    const handleVisibility = () => {
      if (document.visibilityState === "visible" && !revealDone.current) {
        cancelAnimationFrame(waveRafRef.current);
        const dots = dotsRef.current;
        for (let i = 0; i < dots.length; i++) {
          const dot = dots[i];
          if (!dot.el) continue;
          dot.revealed = true;
          dot.wave = 1;
          dot.el.style.opacity = "1";
          dot.el.style.transform = "scale(1)";
          dot.el.style.backgroundColor = rgbStr(DOT_COLOR_SETTLED[0], DOT_COLOR_SETTLED[1], DOT_COLOR_SETTLED[2]);
        }
        revealDone.current = true;
        onCompleteRef.current();
      }
    };
    document.addEventListener("visibilitychange", handleVisibility);

    return () => {
      cancelAnimationFrame(waveRafRef.current);
      document.removeEventListener("visibilitychange", handleVisibility);
    };
  }, [mounted]);

  // Mouse tracking + trail glow animation
  useEffect(() => {
    if (!isFinePointer.current) return;

    const handleMove = (e: MouseEvent) => {
      mouseRef.current = { x: e.clientX, y: e.clientY };
      lastMoveRef.current = performance.now();
    };
    window.addEventListener("mousemove", handleMove);

    const IDLE_THRESHOLD = 150; // ms before trail starts fading

    const animate = () => {
      const dots = dotsRef.current;
      const dragging = isDraggingRef.current;
      const mouseIdle = performance.now() - lastMoveRef.current > IDLE_THRESHOLD;
      const mx = dragging ? -9999 : mouseRef.current.x;
      const my = dragging ? -9999 : mouseRef.current.y;

      for (let i = 0; i < dots.length; i++) {
        const dot = dots[i];
        if (!dot.el || !dot.revealed) continue;

        const dist = Math.hypot(dot.x - mx, dot.y - my);

        if (!dragging && !mouseIdle && dist < GLOW_RADIUS) {
          const intensity = 1 - dist / GLOW_RADIUS;
          const eased = intensity * intensity;
          dot.glow = Math.max(dot.glow, eased);
        } else {
          dot.glow *= TRAIL_DECAY;
          if (dot.glow < TRAIL_THRESHOLD) dot.glow = 0;
        }

        // Only apply trail color if wave has settled
        if (dot.wave < 1) continue;

        if (dot.glow > 0) {
          const g = dot.glow;
          const rv = Math.round(DOT_COLOR_SETTLED[0] + (GREEN_RGB[0] - DOT_COLOR_SETTLED[0]) * g);
          const gv = Math.round(DOT_COLOR_SETTLED[1] + (GREEN_RGB[1] - DOT_COLOR_SETTLED[1]) * g);
          const bv = Math.round(DOT_COLOR_SETTLED[2] + (GREEN_RGB[2] - DOT_COLOR_SETTLED[2]) * g);
          dot.el.style.backgroundColor = `rgb(${rv},${gv},${bv})`;

          dot.el.style.transform = "scale(1)";

          if (g > 0.15) {
            dot.el.style.boxShadow = `0 0 ${12 * g}px rgba(34,197,94,${g * 0.5})`;
          } else {
            dot.el.style.boxShadow = "none";
          }
        } else {
          dot.el.style.backgroundColor = rgbStr(DOT_COLOR_SETTLED[0], DOT_COLOR_SETTLED[1], DOT_COLOR_SETTLED[2]);
          dot.el.style.transform = "scale(1)";
          dot.el.style.boxShadow = "none";
        }
      }

      rafRef.current = requestAnimationFrame(animate);
    };
    rafRef.current = requestAnimationFrame(animate);

    return () => {
      window.removeEventListener("mousemove", handleMove);
      cancelAnimationFrame(rafRef.current);
    };
  }, [dotData]);

  return (
    <div
      ref={containerRef}
      className="fixed inset-0 overflow-hidden pointer-events-none"
      aria-hidden="true"
    >
      {dotData.map((dot, i) => (
        <div
          key={i}
          ref={(el) => {
            if (!dotsRef.current[i]) {
              const alreadySettled = revealDone.current;
              dotsRef.current[i] = { ...dot, el, glow: 0, wave: alreadySettled ? 1 : 0, revealed: alreadySettled };
            } else {
              dotsRef.current[i].el = el;
            }
          }}
          className="absolute rounded-full"
          style={{
            width: DOT_SIZE,
            height: DOT_SIZE,
            left: dot.x - DOT_SIZE / 2,
            top: dot.y - DOT_SIZE / 2,
            backgroundColor: rgbStr(DOT_COLOR_SETTLED[0], DOT_COLOR_SETTLED[1], DOT_COLOR_SETTLED[2]),
            opacity: revealDone.current ? 1 : 0,
            transform: revealDone.current ? "scale(1)" : "scale(0)",
          }}
        />
      ))}
    </div>
  );
}
