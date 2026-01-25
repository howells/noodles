import { useState } from "react";
import { Header } from "./components/Header";
import { SearchFilter } from "./components/SearchFilter";
import { ProjectList } from "./components/ProjectList";

function App() {
  const [filter, setFilter] = useState("");

  return (
    <div className="flex h-full flex-col bg-[var(--bg-primary)]">
      <Header />
      <SearchFilter value={filter} onChange={setFilter} />
      <ProjectList filter={filter} />
    </div>
  );
}

export default App;
