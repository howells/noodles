import type { Project } from "../types";
import { StatusIndicator } from "./StatusIndicator";
import { PortBadge } from "./PortBadge";
import { ActionButtons } from "./ActionButtons";

interface ProjectCardProps {
  project: Project;
}

export function ProjectCard({ project }: ProjectCardProps) {
  const isRunning = project.status === "running";
  const displayPath = project.path.replace(/^\/Users\/[^/]+/, "~");

  return (
    <div className="group mb-1 rounded-lg border border-transparent bg-[var(--bg-secondary)] p-3 transition-colors hover:border-[var(--border)]">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <StatusIndicator status={project.status} />
            <span className="truncate font-medium text-[var(--text-primary)]">
              {project.displayName || project.name}
            </span>
            {project.projectType.type !== "standard" && (
              <span className="shrink-0 rounded bg-[var(--bg-tertiary)] px-1.5 py-0.5 text-[10px] font-medium uppercase text-[var(--text-muted)]">
                {project.projectType.type}
              </span>
            )}
          </div>
          <p className="mt-0.5 truncate text-xs text-[var(--text-muted)]">
            {displayPath}
          </p>

          {/* Running ports */}
          {isRunning && project.runningPorts.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1.5">
              {project.runningPorts.map((port) => (
                <PortBadge
                  key={port.port}
                  port={port.port}
                  label={port.label}
                />
              ))}
            </div>
          )}

          {/* Expected ports when stopped */}
          {!isRunning && project.expectedPorts.length > 0 && (
            <p className="mt-1.5 text-xs text-[var(--text-muted)]">
              Port{project.expectedPorts.length > 1 ? "s" : ""}:{" "}
              {project.expectedPorts.join(", ")}
            </p>
          )}
        </div>

        <ActionButtons project={project} />
      </div>
    </div>
  );
}
