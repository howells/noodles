package projects

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolverFindsPackageRoot(t *testing.T) {
	tmp := t.TempDir()
	projectRoot := filepath.Join(tmp, "app")
	mustMkdir(t, filepath.Join(projectRoot, "src"))
	mustWrite(t, filepath.Join(projectRoot, "package.json"), `{"name":"app"}`)

	resolver := NewResolver()
	project, err := resolver.Resolve(filepath.Join(projectRoot, "src"))
	if err != nil {
		t.Fatalf("Resolve returned error: %v", err)
	}

	if project.Root != projectRoot {
		t.Fatalf("expected root %q, got %q", projectRoot, project.Root)
	}
	if project.DisplayName != "app" {
		t.Fatalf("expected display name app, got %q", project.DisplayName)
	}
}

func TestResolverFindsWorkspaceRoot(t *testing.T) {
	tmp := t.TempDir()
	workspaceRoot := filepath.Join(tmp, "mono")
	appRoot := filepath.Join(workspaceRoot, "apps", "web")
	mustMkdir(t, appRoot)
	mustWrite(t, filepath.Join(workspaceRoot, "package.json"), `{"workspaces":["apps/*"]}`)
	mustWrite(t, filepath.Join(appRoot, "package.json"), `{"name":"web"}`)

	resolver := NewResolver()
	project, err := resolver.Resolve(appRoot)
	if err != nil {
		t.Fatalf("Resolve returned error: %v", err)
	}

	if project.Root != appRoot {
		t.Fatalf("expected app root %q, got %q", appRoot, project.Root)
	}
	if project.WorkspaceRoot != workspaceRoot {
		t.Fatalf("expected workspace root %q, got %q", workspaceRoot, project.WorkspaceRoot)
	}
}

func TestResolverCachesNormalizedCWD(t *testing.T) {
	tmp := t.TempDir()
	projectRoot := filepath.Join(tmp, "cached")
	mustMkdir(t, filepath.Join(projectRoot, "src"))
	mustWrite(t, filepath.Join(projectRoot, "package.json"), `{"name":"cached"}`)

	resolver := NewResolver()
	first, err := resolver.Resolve(filepath.Join(projectRoot, "src"))
	if err != nil {
		t.Fatalf("first resolve returned error: %v", err)
	}
	second, err := resolver.Resolve(filepath.Join(projectRoot, "src", "..", "src"))
	if err != nil {
		t.Fatalf("second resolve returned error: %v", err)
	}

	if first.ID != second.ID {
		t.Fatalf("expected cached normalized cwd to resolve same project, got %q and %q", first.ID, second.ID)
	}
	if resolver.CacheSize() != 1 {
		t.Fatalf("expected one cache entry, got %d", resolver.CacheSize())
	}
}

func TestResolverFallsBackToCWDWithoutMarkers(t *testing.T) {
	tmp := t.TempDir()
	cwd := filepath.Join(tmp, "loose")
	mustMkdir(t, cwd)

	resolver := NewResolver()
	project, err := resolver.Resolve(cwd)
	if err != nil {
		t.Fatalf("Resolve returned error: %v", err)
	}

	if project.Root != cwd {
		t.Fatalf("expected cwd root fallback %q, got %q", cwd, project.Root)
	}
	if project.WorkspaceRoot != cwd {
		t.Fatalf("expected cwd workspace fallback %q, got %q", cwd, project.WorkspaceRoot)
	}
}

func mustMkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
}

func mustWrite(t *testing.T, path string, content string) {
	t.Helper()
	mustMkdir(t, filepath.Dir(path))
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
