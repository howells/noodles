package app

import (
	"context"
	"testing"
	"time"

	"github.com/howells/noodles/internal/ports"
	"github.com/howells/noodles/internal/processes"
	"github.com/howells/noodles/internal/projects"
)

func TestScannerIncludesHighPortsAndAggregatesByPID(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	scanner := NewScanner(
		fakeListenerCollector{listeners: []ports.Listener{
			{PID: 1234, Command: "node", Address: "*", Port: 30000},
			{PID: 1234, Command: "node", Address: "*", Port: 5173},
		}},
		fakeProcessCollector{processes: map[int]processes.Process{
			1234: {
				PID:                 1234,
				ParentPID:           100,
				ProcessGroupID:      1234,
				Command:             "node",
				CommandLine:         "next dev --port 30000",
				CWD:                 "/Users/danielhowells/Sites/example/apps/web",
				ExecutablePath:      "/opt/homebrew/bin/node",
				ResidentMemoryBytes: 2048,
				StartedAt:           now.Add(-time.Minute),
			},
		}},
		fakeProjectResolver{project: projects.Project{
			ID:            "project:example",
			Name:          "web",
			DisplayName:   "web",
			Root:          "/Users/danielhowells/Sites/example/apps/web",
			WorkspaceRoot: "/Users/danielhowells/Sites/example",
		}},
		nowFunc(now),
	)

	snapshot, err := scanner.Scan(context.Background(), Query{})
	if err != nil {
		t.Fatalf("Scan returned error: %v", err)
	}

	if len(snapshot.Services) != 1 {
		t.Fatalf("expected one aggregated service, got %#v", snapshot.Services)
	}
	service := snapshot.Services[0]
	if !equalIntSlices(service.Ports, []int{5173, 30000}) {
		t.Fatalf("expected sorted high ports, got %#v", service.Ports)
	}
	if service.ProjectID != "project:example" || service.ProjectRoot == "" {
		t.Fatalf("expected project fields, got %+v", service)
	}
	if service.SourceLabel != "dev-server" || len(service.SourceEvidence) == 0 {
		t.Fatalf("expected classification evidence, got %+v", service)
	}
	if snapshot.Metadata.SnapshotID == "" {
		t.Fatal("expected non-empty snapshot id")
	}
}

type fakeListenerCollector struct {
	listeners []ports.Listener
}

func (c fakeListenerCollector) Collect(ctx context.Context) ([]ports.Listener, error) {
	return c.listeners, nil
}

type fakeProcessCollector struct {
	processes map[int]processes.Process
}

func (c fakeProcessCollector) Collect(ctx context.Context, pids []int) (map[int]processes.Process, error) {
	return c.processes, nil
}

type fakeProjectResolver struct {
	project projects.Project
}

func (r fakeProjectResolver) Resolve(cwd string) (projects.Project, error) {
	return r.project, nil
}

func nowFunc(now time.Time) func() time.Time {
	return func() time.Time { return now }
}

func equalIntSlices(a []int, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
