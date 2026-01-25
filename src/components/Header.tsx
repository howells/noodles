import { Settings, RefreshCw } from "./icons";
import { useStore } from "../store";

interface HeaderProps {
  onRefresh: () => void;
}

export function Header({ onRefresh }: HeaderProps) {
  const isScanning = useStore((s) => s.isScanning);

  return (
    <header className="flex items-center justify-between border-b border-[var(--border)] px-4 py-3">
      <h1 className="text-lg font-semibold text-[var(--text-primary)]">
        nodles
      </h1>
      <div className="flex items-center gap-2">
        <button
          onClick={onRefresh}
          disabled={isScanning}
          className={`rounded-md p-1.5 text-[var(--text-secondary)] transition-colors hover:bg-[var(--bg-tertiary)] hover:text-[var(--text-primary)] disabled:opacity-50 ${
            isScanning ? "animate-spin" : ""
          }`}
          title="Refresh projects"
        >
          <RefreshCw className="h-4 w-4" />
        </button>
        <button
          className="rounded-md p-1.5 text-[var(--text-secondary)] transition-colors hover:bg-[var(--bg-tertiary)] hover:text-[var(--text-primary)]"
          title="Settings"
        >
          <Settings className="h-4 w-4" />
        </button>
      </div>
    </header>
  );
}
