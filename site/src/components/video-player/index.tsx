"use client";

import { MediaController } from "media-chrome/react";
import type { ComponentProps, CSSProperties } from "react";

const variables = {
  "--media-primary-color": "var(--color-green)",
  "--media-secondary-color": "var(--color-card)",
  "--media-text-color": "var(--color-card-text)",
  "--media-background-color": "transparent",
  "--media-control-hover-background": "rgba(0,0,0,0.1)",
  "--media-range-track-background": "rgba(0,0,0,0.15)",
} as CSSProperties;

export type VideoPlayerProps = ComponentProps<typeof MediaController>;

export const VideoPlayer = ({ style, ...props }: VideoPlayerProps) => (
  <MediaController
    style={{
      ...variables,
      ...style,
    }}
    {...props}
  />
);

export const VideoPlayerContent = ({
  className,
  ...props
}: ComponentProps<"video">) => (
  <video className={className} suppressHydrationWarning {...props} />
);
