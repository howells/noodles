import { ProjectCard } from "./ProjectCard";
import { useStore } from "../store";

export function ProjectList() {
  const projects = useStore((s) => s.projects);
  const filter = useStore((s) => s.filter);
  const isScanning = useStore((s) => s.isScanning);
  const scanError = useStore((s) => s.scanError);

  const filteredProjects = projects.filter(
    (p) =>
      !p.hidden &&
      (p.name.toLowerCase().includes(filter.toLowerCase()) ||
        p.id.toLowerCase().includes(filter.toLowerCase()) ||
        p.path.toLowerCase().includes(filter.toLowerCase()))
  );

  const runningProjects = filteredProjects.filter((p) => p.status === "running" || p.status === "starting" || p.status === "stopping");
  const stoppedProjects = filteredProjects.filter((p) => p.status === "stopped" || p.status === "error");

  if (scanError) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 px-4 text-center">
        <p className="text-[var(--error)]">Failed to scan projects</p>
        <p className="text-sm text-[var(--text-muted)]">{scanError}</p>
      </div>
    );
  }

  if (isScanning && projects.length === 0) {
    return (
      <div className="flex h-full items-center justify-center">
        <p className="text-[var(--text-muted)]">Scanning projects...</p>
      </div>
    );
  }

  if (filteredProjects.length === 0 && filter) {
    return (
      <div className="flex h-full items-center justify-center">
        <p className="text-[var(--text-muted)]">No projects match "{filter}"</p>
      </div>
    );
  }

  if (projects.length === 0) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 px-4 text-center">
        <p className="text-[var(--text-muted)]">No projects found</p>
        <p className="text-xs text-[var(--text-muted)]">
          Make sure ~/Sites contains projects with package.json and a dev script
        </p>
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto">
      {runningProjects.length > 0 && (
        <section>
          <div className="sticky top-0 z-10 bg-[var(--bg-primary)] px-4 py-2">
            <h2 className="text-xs font-medium uppercase tracking-wider text-[var(--text-muted)]">
              Running ({runningProjects.length})
            </h2>
          </div>
          <div className="px-2">
            {runningProjects.map((project) => (
              <ProjectCard key={project.id} project={project} />
            ))}
          </div>
        </section>
      )}

      {stoppedProjects.length > 0 && (
        <section>
          <div className="sticky top-0 z-10 bg-[var(--bg-primary)] px-4 py-2">
            <h2 className="text-xs font-medium uppercase tracking-wider text-[var(--text-muted)]">
              Available ({stoppedProjects.length})
            </h2>
          </div>
          <div className="px-2">
            {stoppedProjects.map((project) => (
              <ProjectCard key={project.id} project={project} />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
