package projects

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Project struct {
	ID            string
	Name          string
	DisplayName   string
	Root          string
	WorkspaceRoot string
}

type Resolver struct {
	cache map[string]Project
}

func NewResolver() *Resolver {
	return &Resolver{cache: make(map[string]Project)}
}

func (r *Resolver) Resolve(cwd string) (Project, error) {
	normalized, err := filepath.Abs(filepath.Clean(cwd))
	if err != nil {
		return Project{}, fmt.Errorf("normalize cwd: %w", err)
	}

	if cached, ok := r.cache[normalized]; ok {
		return cached, nil
	}

	root := findNearestProjectRoot(normalized)
	if root == "" {
		root = normalized
	}

	workspaceRoot := findNearestWorkspaceRoot(root)
	if workspaceRoot == "" {
		workspaceRoot = root
	}

	project := Project{
		ID:            projectID(root),
		Name:          filepath.Base(root),
		DisplayName:   filepath.Base(root),
		Root:          root,
		WorkspaceRoot: workspaceRoot,
	}

	r.cache[normalized] = project
	return project, nil
}

func (r *Resolver) CacheSize() int {
	return len(r.cache)
}

func findNearestProjectRoot(start string) string {
	current := start
	for {
		if markerExists(filepath.Join(current, ".git")) || markerExists(filepath.Join(current, "package.json")) {
			return current
		}

		parent := filepath.Dir(current)
		if parent == current {
			return ""
		}
		current = parent
	}
}

func findNearestWorkspaceRoot(start string) string {
	current := start
	for {
		if packageHasWorkspaces(filepath.Join(current, "package.json")) {
			return current
		}

		parent := filepath.Dir(current)
		if parent == current {
			return ""
		}
		current = parent
	}
}

func markerExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func packageHasWorkspaces(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}

	var pkg struct {
		Workspaces json.RawMessage `json:"workspaces"`
	}
	if err := json.Unmarshal(data, &pkg); err != nil {
		return false
	}
	return len(strings.TrimSpace(string(pkg.Workspaces))) > 0 && string(pkg.Workspaces) != "null"
}

func projectID(root string) string {
	sum := sha1.Sum([]byte(root))
	return "project:" + hex.EncodeToString(sum[:])
}
