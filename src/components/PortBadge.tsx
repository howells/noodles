interface PortBadgeProps {
  port: number;
  label?: string;
  onClick?: () => void;
}

export function PortBadge({ port, label, onClick }: PortBadgeProps) {
  return (
    <button
      onClick={onClick}
      className="inline-flex items-center gap-1 rounded-md bg-[var(--bg-tertiary)] px-2 py-1 text-xs font-medium text-[var(--text-secondary)] transition-colors hover:bg-[var(--border)] hover:text-[var(--text-primary)]"
      title={`Open localhost:${port} in browser`}
    >
      <span className="font-mono">{port}</span>
      {label && (
        <span className="text-[var(--text-muted)]">· {label}</span>
      )}
    </button>
  );
}
