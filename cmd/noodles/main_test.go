package main

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/howells/noodles/internal/app"
	"github.com/howells/noodles/internal/killer"
)

func TestListCommandFormatsServiceRowsWithPortAndMemory(t *testing.T) {
	core := &fakeCLIClient{
		snapshot: app.Snapshot{Services: []app.Service{
			{
				ID:                  "service-1",
				ProjectDisplayName:  "materia",
				Command:             "node",
				Ports:               []int{5173},
				ResidentMemoryBytes: 128 * 1024 * 1024,
				SourceLabel:         "dev-server",
			},
		}},
	}
	stdout := &bytes.Buffer{}

	if err := run(context.Background(), core, stdout, bytes.NewBuffer(nil), []string{"list", "--sort", "memory"}); err != nil {
		t.Fatalf("run returned error: %v", err)
	}

	output := stdout.String()
	for _, want := range []string{"materia", "5173", "128.0 MB", "node"} {
		if !strings.Contains(output, want) {
			t.Fatalf("expected output to contain %q, got:\n%s", want, output)
		}
	}
	if core.scanQuery.SortBy != app.SortByMemory {
		t.Fatalf("expected memory sort query, got %#v", core.scanQuery)
	}
}

func TestAmbiguousProjectDisplayNameReturnsCandidateRoots(t *testing.T) {
	snapshot := app.Snapshot{Projects: []app.Project{
		{ID: "one", DisplayName: "materia", Root: "/Users/danielhowells/Sites/materia"},
		{ID: "two", DisplayName: "materia", Root: "/Users/danielhowells/Sites/client/materia"},
	}}

	_, err := SelectProject(snapshot, "materia", "")
	var ambiguous *AmbiguousProjectError
	if !errors.As(err, &ambiguous) {
		t.Fatalf("expected ambiguous project error, got %v", err)
	}
	if len(ambiguous.CandidateRoots) != 2 {
		t.Fatalf("expected candidate roots, got %#v", ambiguous.CandidateRoots)
	}
}

func TestProjectRootSelectsExactRoot(t *testing.T) {
	snapshot := app.Snapshot{Projects: []app.Project{
		{ID: "one", DisplayName: "materia", Root: "/Users/danielhowells/Sites/materia"},
		{ID: "two", DisplayName: "materia", Root: "/Users/danielhowells/Sites/client/materia"},
	}}

	selection, err := SelectProject(snapshot, "", "/Users/danielhowells/Sites/client/materia")
	if err != nil {
		t.Fatalf("SelectProject returned error: %v", err)
	}
	if selection.Project.ID != "two" {
		t.Fatalf("expected exact root selection, got %#v", selection)
	}
}

type fakeCLIClient struct {
	scanQuery   app.Query
	snapshot    app.Snapshot
	killRequest killer.KillRequest
	killResult  killer.KillResult
}

func (c *fakeCLIClient) Scan(_ context.Context, query app.Query) (app.Snapshot, error) {
	c.scanQuery = query
	return c.snapshot, nil
}

func (c *fakeCLIClient) KillService(_ context.Context, request killer.KillRequest) (killer.KillResult, error) {
	c.killRequest = request
	return c.killResult, nil
}
