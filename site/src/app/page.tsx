"use client";

import { Cards } from "@/components/Cards";
import { DotGrid } from "@/components/DotGrid";
import { useCallback, useRef, useState } from "react";

export default function Home() {
  const [cardsVisible, setCardsVisible] = useState(false);
  const [videoOpen, setVideoOpen] = useState(false);
  const isDraggingRef = useRef(false);

  const handleGridComplete = useCallback(() => {
    setCardsVisible(true);
  }, []);

  const handleVideoClick = useCallback(() => {
    setVideoOpen(true);
  }, []);

  const handleVideoClose = useCallback(() => {
    setVideoOpen(false);
  }, []);

  return (
    <main className="fixed inset-0 overflow-hidden" style={{ background: "#ffffff" }}>
      <DotGrid onComplete={handleGridComplete} isDraggingRef={isDraggingRef} />
      <Cards
        visible={cardsVisible}
        videoOpen={videoOpen}
        onVideoClick={handleVideoClick}
        onVideoClose={handleVideoClose}
        isDraggingRef={isDraggingRef}
      />
    </main>
  );
}
