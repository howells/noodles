package app

import (
	"testing"
	"time"
)

func TestBuildViewDefaultSortsByMemoryDescending(t *testing.T) {
	snapshot := Snapshot{Services: []Service{
		serviceFixture("low", "proj-a", "node", []int{3000}, 10, true, "dev-server"),
		serviceFixture("high", "proj-b", "node", []int{3001}, 100, true, "dev-server"),
	}}

	view := BuildView(snapshot, Query{})

	if got := view.Services[0].ID; got != "high" {
		t.Fatalf("expected high memory service first, got %q", got)
	}
}

func TestBuildViewKeepsTieBreakersAscending(t *testing.T) {
	snapshot := Snapshot{Services: []Service{
		serviceFixture("zulu", "proj-z", "node", []int{4000}, 100, true, "dev-server"),
		serviceFixture("alpha", "proj-a", "node", []int{3000}, 100, true, "dev-server"),
	}}

	view := BuildView(snapshot, Query{SortBy: SortByMemory, SortDirection: SortDirectionDesc})

	if got := view.Services[0].ID; got != "alpha" {
		t.Fatalf("expected ascending project tiebreaker, got %q", got)
	}
}

func TestBuildViewSortsByLowestPort(t *testing.T) {
	snapshot := Snapshot{Services: []Service{
		serviceFixture("second", "proj-a", "node", []int{4000, 5000}, 10, true, "dev-server"),
		serviceFixture("first", "proj-b", "node", []int{3000, 9000}, 10, true, "dev-server"),
	}}

	view := BuildView(snapshot, Query{SortBy: SortByPort, SortDirection: SortDirectionAsc})

	if got := view.Services[0].ID; got != "first" {
		t.Fatalf("expected lowest port service first, got %q", got)
	}
}

func TestBuildViewCanHideSystemRows(t *testing.T) {
	snapshot := Snapshot{Services: []Service{
		serviceFixture("system", "proj-a", "ControlCenter", []int{5000}, 10, false, "system"),
		serviceFixture("dev", "proj-b", "node", []int{3000}, 10, true, "dev-server"),
	}}

	view := BuildView(snapshot, Query{HideSystem: true})

	if len(view.Services) != 1 || view.Services[0].ID != "dev" {
		t.Fatalf("expected only dev service, got %#v", view.Services)
	}
}

func TestBuildViewGroupsProjectsWithAggregates(t *testing.T) {
	snapshot := Snapshot{Services: []Service{
		serviceFixture("one", "project:app", "node", []int{3000}, 100, true, "dev-server"),
		serviceFixture("two", "project:app", "storybook", []int{6006}, 50, false, "storybook"),
		serviceFixture("three", "project:other", "node", []int{5173}, 25, true, "dev-server"),
	}}

	view := BuildView(snapshot, Query{GroupBy: GroupByProject})

	group := findGroup(view.Groups, "project:app")
	if group == nil {
		t.Fatalf("expected project group, got %#v", view.Groups)
	}
	if group.TotalResidentMemoryBytes != 150 {
		t.Fatalf("expected aggregate memory 150, got %d", group.TotalResidentMemoryBytes)
	}
	if group.KillableServiceCount != 1 || group.ExcludedServiceCount != 1 {
		t.Fatalf("unexpected killable/excluded counts: %+v", group)
	}
	if !equalIntSlices(group.Ports, []int{3000, 6006}) {
		t.Fatalf("expected aggregate ports, got %#v", group.Ports)
	}
}

func TestBuildViewSearchMatchesProjectCommandAndPort(t *testing.T) {
	snapshot := Snapshot{Services: []Service{
		serviceFixture("project", "project:app", "node", []int{3000}, 10, true, "dev-server"),
		serviceFixture("command", "project:other", "storybook", []int{6006}, 10, true, "storybook"),
		serviceFixture("port", "project:other", "node", []int{5173}, 10, true, "dev-server"),
	}}
	snapshot.Services[0].ProjectDisplayName = "materia"

	for _, tc := range []struct {
		search string
		want   string
	}{
		{search: "materia", want: "project"},
		{search: "storybook", want: "command"},
		{search: "5173", want: "port"},
	} {
		view := BuildView(snapshot, Query{Search: tc.search})
		if len(view.Services) != 1 || view.Services[0].ID != tc.want {
			t.Fatalf("search %q returned %#v, want %q", tc.search, view.Services, tc.want)
		}
	}
}

func serviceFixture(id string, projectID string, command string, ports []int, memory uint64, killable bool, source string) Service {
	return Service{
		ID:                  id,
		PID:                 len(id),
		Command:             command,
		CommandLine:         command + " dev",
		CWD:                 "/Users/danielhowells/Sites/" + projectID,
		ProjectID:           projectID,
		ProjectName:         projectID,
		ProjectDisplayName:  projectID,
		ProjectRoot:         "/Users/danielhowells/Sites/" + projectID,
		Ports:               ports,
		ResidentMemoryBytes: memory,
		StartedAt:           time.Unix(1_700_000_000, 0),
		AgeSeconds:          60,
		SourceLabel:         source,
		Killable:            killable,
	}
}

func findGroup(groups []Group, id string) *Group {
	for i := range groups {
		if groups[i].ID == id {
			return &groups[i]
		}
	}
	return nil
}
