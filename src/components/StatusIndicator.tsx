import type { ProjectStatus } from "../types";

interface StatusIndicatorProps {
  status: ProjectStatus;
}

export function StatusIndicator({ status }: StatusIndicatorProps) {
  const colors: Record<ProjectStatus, string> = {
    stopped: "bg-[var(--text-muted)]",
    starting: "bg-[var(--warning)]",
    running: "bg-[var(--success)]",
    stopping: "bg-[var(--warning)]",
    error: "bg-[var(--error)]",
  };

  const pulseStates: ProjectStatus[] = ["starting", "stopping"];
  const shouldPulse = pulseStates.includes(status);

  return (
    <span className="relative flex h-2.5 w-2.5 shrink-0">
      {shouldPulse && (
        <span
          className={`absolute inline-flex h-full w-full animate-ping rounded-full opacity-75 ${colors[status]}`}
        />
      )}
      <span
        className={`relative inline-flex h-2.5 w-2.5 rounded-full ${colors[status]}`}
      />
    </span>
  );
}
