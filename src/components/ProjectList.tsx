import { ProjectCard } from "./ProjectCard";
import type { Project } from "../types";

// Mock data for development
const MOCK_PROJECTS: Project[] = [
  {
    id: "obliq",
    name: "obliq",
    path: "/Users/danielhowells/Sites/obliq",
    devCommand: "next dev --port 9000",
    expectedPorts: [9000],
    packageManager: "pnpm",
    projectType: { type: "standard" },
    favorite: false,
    hidden: false,
    status: "running",
    runningPorts: [{ port: 9000, pid: 52778, processName: "node" }],
  },
  {
    id: "aloud",
    name: "aloud",
    path: "/Users/danielhowells/Sites/aloud",
    devCommand: "next dev",
    expectedPorts: [3000],
    packageManager: "pnpm",
    projectType: { type: "standard" },
    favorite: false,
    hidden: false,
    status: "running",
    runningPorts: [{ port: 3000, pid: 18698, processName: "node" }],
  },
  {
    id: "reccs",
    name: "reccs",
    path: "/Users/danielhowells/Sites/reccs",
    devCommand: "next dev --port 5000",
    expectedPorts: [5000],
    packageManager: "pnpm",
    projectType: { type: "standard" },
    favorite: false,
    hidden: false,
    status: "stopped",
    runningPorts: [],
  },
  {
    id: "siteinspire",
    name: "siteinspire",
    path: "/Users/danielhowells/Sites/siteinspire",
    devCommand: "turbo dev",
    expectedPorts: [3000],
    packageManager: "pnpm",
    projectType: { type: "turborepo", apps: ["apps/web"] },
    favorite: true,
    hidden: false,
    status: "stopped",
    runningPorts: [],
  },
  {
    id: "tersa",
    name: "tersa",
    path: "/Users/danielhowells/Sites/tersa",
    devCommand:
      'concurrently "next dev --port 6000" "supabase start" "email dev --port 6001"',
    expectedPorts: [6000, 6001],
    packageManager: "pnpm",
    projectType: { type: "standard" },
    favorite: false,
    hidden: false,
    status: "stopped",
    runningPorts: [],
  },
];

interface ProjectListProps {
  filter: string;
}

export function ProjectList({ filter }: ProjectListProps) {
  const filteredProjects = MOCK_PROJECTS.filter(
    (p) =>
      !p.hidden &&
      (p.name.toLowerCase().includes(filter.toLowerCase()) ||
        p.path.toLowerCase().includes(filter.toLowerCase()))
  );

  const runningProjects = filteredProjects.filter((p) => p.status === "running");
  const stoppedProjects = filteredProjects.filter((p) => p.status !== "running");

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

      {filteredProjects.length === 0 && (
        <div className="flex h-full items-center justify-center text-[var(--text-muted)]">
          <p>No projects found</p>
        </div>
      )}
    </div>
  );
}
