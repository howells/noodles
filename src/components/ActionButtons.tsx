import type { Project } from "../types";
import { Globe, Code, RotateCw, Square, Play } from "./icons";

interface ActionButtonsProps {
  project: Project;
}

export function ActionButtons({ project }: ActionButtonsProps) {
  const isRunning = project.status === "running";
  const isTransitioning =
    project.status === "starting" || project.status === "stopping";

  if (isTransitioning) {
    return (
      <div className="flex shrink-0 items-center gap-1">
        <span className="text-xs text-[var(--text-muted)]">
          {project.status === "starting" ? "Starting..." : "Stopping..."}
        </span>
      </div>
    );
  }

  if (isRunning) {
    return (
      <div className="flex shrink-0 items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100">
        <IconButton
          icon={Globe}
          title="Open in browser"
          onClick={() => {
            // Will open first port in browser
          }}
        />
        <IconButton
          icon={Code}
          title="Open in editor"
          onClick={() => {
            // Will open in editor
          }}
        />
        <IconButton
          icon={RotateCw}
          title="Restart"
          onClick={() => {
            // Will restart
          }}
        />
        <IconButton
          icon={Square}
          title="Stop"
          onClick={() => {
            // Will stop
          }}
          variant="danger"
        />
      </div>
    );
  }

  return (
    <div className="flex shrink-0 items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100">
      <IconButton
        icon={Code}
        title="Open in editor"
        onClick={() => {
          // Will open in editor
        }}
      />
      <IconButton
        icon={Play}
        title="Start"
        onClick={() => {
          // Will start
        }}
        variant="primary"
      />
    </div>
  );
}

interface IconButtonProps {
  icon: React.FC<{ className?: string }>;
  title: string;
  onClick: () => void;
  variant?: "default" | "primary" | "danger";
}

function IconButton({
  icon: Icon,
  title,
  onClick,
  variant = "default",
}: IconButtonProps) {
  const variantClasses = {
    default:
      "text-[var(--text-secondary)] hover:bg-[var(--bg-tertiary)] hover:text-[var(--text-primary)]",
    primary:
      "text-[var(--accent)] hover:bg-[var(--accent)] hover:text-white",
    danger:
      "text-[var(--text-secondary)] hover:bg-[var(--error)] hover:text-white",
  };

  return (
    <button
      onClick={onClick}
      title={title}
      className={`rounded-md p-1.5 transition-colors ${variantClasses[variant]}`}
    >
      <Icon className="h-4 w-4" />
    </button>
  );
}
