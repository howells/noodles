import { Header } from "./components/Header";
import { SearchFilter } from "./components/SearchFilter";
import { ProjectList } from "./components/ProjectList";
import { useStore } from "./store";
import { useProjects, usePorts, useConfig } from "./hooks";

function App() {
  const filter = useStore((s) => s.filter);
  const setFilter = useStore((s) => s.setFilter);

  // Initialize hooks - they handle their own effects
  useConfig();
  const { scan } = useProjects();
  usePorts();

  return (
    <div className="flex h-full flex-col bg-[var(--bg-primary)]">
      <Header onRefresh={scan} />
      <SearchFilter value={filter} onChange={setFilter} />
      <ProjectList />
    </div>
  );
}

export default App;
