"use client";

import { AnimatePresence, motion, useMotionValue, useMotionValueEvent, useSpring } from "motion/react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useMediaQuery } from "usehooks-ts";
import {
  VideoPlayer,
  VideoPlayerContent,
} from "@/components/video-player";

type CardDef = {
  id: string;
  rotation: number;
  offsetX: number;
  offsetY: number;
  zIndex: number;
  delay: number;
};

const entranceSpring = { type: "spring" as const, stiffness: 400, damping: 28 };
const dragSpring = { stiffness: 500, damping: 30 };
const modalSpring = { type: "spring" as const, stiffness: 350, damping: 26 };

// Collins shadow
const shadowLg =
  "0px 211px 127px 0px rgba(0,0,0,.04), 0px 94px 94px 0px rgba(0,0,0,.07), 0px 23px 52px 0px rgba(0,0,0,.08)";

const cardDefs: CardDef[] = [
  {
    id: "title",
    rotation: -6,
    offsetX: -280,
    offsetY: -88,
    zIndex: 3,
    delay: 0,
  },
  {
    id: "description",
    rotation: 3,
    offsetX: -120,
    offsetY: 30,
    zIndex: 2,
    delay: 0.15,
  },
  {
    id: "video",
    rotation: -2,
    offsetX: 100,
    offsetY: -160,
    zIndex: 1,
    delay: 0.3,
  },
  {
    id: "icon",
    rotation: -5,
    offsetX: -260,
    offsetY: 128,
    zIndex: 4,
    delay: 0.45,
  },
];

function DraggableCard({
  def,
  visible,
  videoOpen,
  isMobile,
  onClick,
  isDraggingRef,
  children,
}: {
  def: CardDef;
  visible: boolean;
  videoOpen: boolean;
  isMobile: boolean;
  onClick?: () => void;
  isDraggingRef: React.RefObject<boolean>;
  children: React.ReactNode;
}) {
  const dragX = useMotionValue(0);
  const dragY = useMotionValue(0);
  const dragScale = useMotionValue(1);

  // Persistent offset — accumulates across drags
  const offsetRef = useRef({ x: 0, y: 0 });
  const springX = useSpring(dragX, dragSpring);
  const springY = useSpring(dragY, dragSpring);
  const springDragScale = useSpring(dragScale, { stiffness: 600, damping: 30 });

  const isVideo = def.id === "video";
  const didDragRef = useRef(false);

  // Track video close to stagger the return via spring physics
  const wasVideoOpen = useRef(false);
  const closingFromVideo = !videoOpen && wasVideoOpen.current;
  useEffect(() => {
    wasVideoOpen.current = videoOpen;
  }, [videoOpen]);

  // Reset drag offset when video opens so card returns to layout position
  useEffect(() => {
    if (videoOpen) {
      dragX.jump(0);
      dragY.jump(0);
      offsetRef.current = { x: 0, y: 0 };
    }
  }, [videoOpen, dragX, dragY]);

  const getAnimateTarget = () => {
    if (!visible) {
      return isMobile
        ? { y: 40, opacity: 0, scale: 0.95, rotate: 0 }
        : { x: def.offsetX, y: 600, opacity: 0, scale: 1, rotate: def.rotation };
    }
    if (isMobile) {
      return { y: 0, opacity: 1, scale: 1, rotate: 0 };
    }
    if (videoOpen && isVideo) {
      const vw = typeof window !== "undefined" ? window.innerWidth : 1200;
      const targetWidth = Math.min(vw - 120, 900);
      const scale = targetWidth / 560;
      return { x: 0, y: 0, opacity: 1, scale, rotate: 0 };
    }
    if (videoOpen && !isVideo) {
      const scatter: Record<string, [number, number]> = {
        title: [-500, -200],
        description: [-400, 250],
        icon: [400, 200],
      };
      const [sx, sy] = scatter[def.id] ?? [-400, 250];
      return { x: sx, y: sy, opacity: 0.6, scale: 0.9, rotate: def.rotation };
    }
    return { x: def.offsetX, y: def.offsetY, opacity: 1, scale: 1, rotate: def.rotation };
  };

  if (isMobile) {
    return (
      <motion.div
        initial={{ y: 40, opacity: 0, scale: 0.95, rotate: 0 }}
        animate={getAnimateTarget()}
        transition={{
          ...entranceSpring,
          delay: visible ? def.delay : 0,
          opacity: { duration: 0.3, delay: visible ? def.delay : 0 },
        }}
        onClick={onClick}
      >
        {children}
      </motion.div>
    );
  }

  return (
    <div
      className="absolute inset-0 pointer-events-none flex items-center justify-center"
      style={{ zIndex: videoOpen && isVideo ? 50 : def.zIndex }}
    >
      <motion.div
        initial={{ x: def.offsetX, y: 600, opacity: 0, scale: 1, rotate: def.rotation }}
        animate={getAnimateTarget()}
        transition={
          closingFromVideo
            ? isVideo
              ? { type: "spring" as const, stiffness: 500, damping: 28 }
              : { type: "spring" as const, stiffness: 220, damping: 24 }
            : {
                ...entranceSpring,
                delay: !visible ? 0 : videoOpen ? 0 : def.delay,
                opacity: { duration: 0.3, delay: !visible ? 0 : videoOpen ? 0 : def.delay },
              }
        }
      >
        <motion.div
          className={`pointer-events-auto select-none ${videoOpen && isVideo ? "" : "cursor-grab active:cursor-grabbing"}`}
          style={{
            x: videoOpen ? 0 : springX,
            y: videoOpen ? 0 : springY,
            scale: springDragScale,
          }}
          drag={!videoOpen}
          dragMomentum={false}
          onDragStart={() => {
            didDragRef.current = true;
            dragScale.set(1.04);
            (isDraggingRef as React.MutableRefObject<boolean>).current = true;
          }}
          onDrag={(_, info) => {
            dragX.jump(offsetRef.current.x + info.offset.x);
            dragY.jump(offsetRef.current.y + info.offset.y);
          }}
          onDragEnd={(_, info) => {
            offsetRef.current.x += info.offset.x;
            offsetRef.current.y += info.offset.y;
            dragX.set(offsetRef.current.x);
            dragY.set(offsetRef.current.y);
            dragScale.set(1);
            (isDraggingRef as React.MutableRefObject<boolean>).current = false;
          }}
          whileTap={videoOpen ? undefined : { scale: 0.97 }}
          onClick={() => {
            if (didDragRef.current) {
              didDragRef.current = false;
              return;
            }
            onClick?.();
          }}
        >
          {children}
        </motion.div>
      </motion.div>
    </div>
  );
}

function TitleCard() {
  return (
    <div
      className="rounded-2xl px-10 py-8"
      style={{
        backgroundColor: "var(--color-card)",
        boxShadow: shadowLg,
      }}
    >
      <h1
        className="text-5xl font-bold tracking-tight whitespace-nowrap"
        style={{
          fontFamily: "var(--font-display), system-ui, sans-serif",
          color: "var(--color-card-text)",
        }}
      >
        Noodles
      </h1>
    </div>
  );
}

function DescriptionCard() {
  return (
    <div
      className="rounded-2xl px-8 py-7 max-w-xs"
      style={{
        backgroundColor: "var(--color-card)",
        boxShadow: shadowLg,
      }}
    >
      <p
        className="text-base leading-relaxed"
        style={{
          fontFamily: "var(--font-body), system-ui, sans-serif",
          color: "var(--color-card-text-secondary)",
        }}
      >
        A tiny menu bar app that manages your Node.js dev servers. Start, stop,
        and monitor everything from one place. Made by{" "}
        <a
          href="https://danielhowells.com"
          target="_blank"
          rel="noopener noreferrer"
          className="underline decoration-[0.5px] underline-offset-4 hover:text-[#22c55e] hover:decoration-[#22c55e] transition-colors"
          onClick={(e) => e.stopPropagation()}
        >
          Howells
        </a>
        .
      </p>
    </div>
  );
}

function VideoCard({ expanded }: { expanded: boolean }) {
  return (
    <div
      className="rounded-2xl overflow-hidden relative"
      style={{
        backgroundColor: "var(--color-card)",
        boxShadow: expanded ? shadowLg : shadowLg,
        width: 560,
        aspectRatio: "4/3",
        transformOrigin: "bottom left",
      }}
    >
      <VideoPlayer
        style={{ width: "100%", height: "100%", display: "block" }}
        noDefaultStore
      >
        <VideoPlayerContent
          slot="media"
          src="/noodles-demo.mp4"
          playsInline
          preload="auto"
          autoPlay
          muted
          loop
          style={{ width: "100%", height: "100%", objectFit: "cover" }}
        />
      </VideoPlayer>
    </div>
  );
}

function IconCard() {
  return (
    <div
      className="rounded-[22px] overflow-hidden"
      style={{ boxShadow: shadowLg, width: 96, height: 96 }}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/app-icon.png" alt="Noodles" className="w-full h-full" draggable={false} />
    </div>
  );
}

export function Cards({
  visible,
  videoOpen,
  onVideoClick,
  onVideoClose,
  isDraggingRef,
}: {
  visible: boolean;
  videoOpen: boolean;
  onVideoClick: () => void;
  onVideoClose: () => void;
  isDraggingRef: React.RefObject<boolean>;
}) {
  const isMobile = useMediaQuery("(max-width: 768px)");
  const handleIconClick = useCallback(() => {
    window.open(
      "https://github.com/howells/noodles-app/releases/latest/download/Noodles.dmg",
      "_blank",
    );
  }, []);

  // Escape key to close video
  useEffect(() => {
    if (!videoOpen) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onVideoClose();
    };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [videoOpen, onVideoClose]);

  // Mobile order: title, description, video, icon
  const mobileOrder = ["title", "description", "video", "icon"] as const;

  if (isMobile) {
    return (
      <div className="fixed inset-0 overflow-y-auto">
        <div className="flex flex-col items-center gap-5 px-6 py-16">
          {mobileOrder.map((id) => {
            const def = cardDefs.find((d) => d.id === id)!;
            return (
              <DraggableCard
                key={def.id}
                def={def}
                visible={visible}
                videoOpen={false}
                isMobile
                isDraggingRef={isDraggingRef}
                onClick={def.id === "icon" ? handleIconClick : def.id === "video" ? onVideoClick : undefined}
              >
                {def.id === "title" && <TitleCard />}
                {def.id === "description" && <DescriptionCard />}
                {def.id === "video" && <VideoCard expanded={false} />}
                {def.id === "icon" && <IconCard />}
              </DraggableCard>
            );
          })}
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="fixed inset-0">
        {/* Backdrop — inside the same stacking context as cards */}
        <AnimatePresence>
          {videoOpen && (
            <motion.div
              className="absolute inset-0"
              style={{
                backgroundColor: "rgba(0, 0, 0, 0.7)",
                backdropFilter: "blur(12px)",
                WebkitBackdropFilter: "blur(12px)",
                zIndex: 40,
              }}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.3 }}
              onClick={onVideoClose}
            />
          )}
        </AnimatePresence>
        {/* Floating close card */}
        <AnimatePresence>
          {videoOpen && (
            <motion.button
              onClick={onVideoClose}
              className="absolute top-8 right-8 w-10 h-10 rounded-xl flex items-center justify-center cursor-pointer"
              style={{
                backgroundColor: "var(--color-card)",
                boxShadow: shadowLg,
                zIndex: 51,
              }}
              initial={{ opacity: 0, scale: 0, rotate: -20 }}
              animate={{ opacity: 1, scale: 1, rotate: 3 }}
              exit={{ opacity: 0, scale: 0, rotate: -20 }}
              transition={{ type: "spring", stiffness: 500, damping: 22, delay: 0.15 }}
              whileHover={{ scale: 1.1, rotate: -3 }}
              whileTap={{ scale: 0.9 }}
            >
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path d="M1 1l12 12M13 1L1 13" stroke="var(--color-card-text)" strokeWidth="2" strokeLinecap="round" />
              </svg>
            </motion.button>
          )}
        </AnimatePresence>
        {cardDefs.map((def) => (
          <DraggableCard
            key={def.id}
            def={def}
            visible={visible}
            videoOpen={videoOpen}
            isMobile={false}
            isDraggingRef={isDraggingRef}
            onClick={
              def.id === "video"
                ? videoOpen
                  ? undefined
                  : onVideoClick
                : def.id === "icon"
                  ? handleIconClick
                  : undefined
            }
          >
            {def.id === "title" && <TitleCard />}
            {def.id === "description" && <DescriptionCard />}
            {def.id === "video" && <VideoCard expanded={videoOpen} />}
            {def.id === "icon" && <IconCard />}
          </DraggableCard>
        ))}
      </div>
    </>
  );
}
