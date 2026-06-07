package app

import (
	"strings"
	"testing"
	"time"
)

func TestServiceIDIsStableForPortOrdering(t *testing.T) {
	startedAt := time.Unix(1_700_000_000, 123)

	first := ServiceID(1234, startedAt, "/opt/homebrew/bin/node", "node", []int{5173, 3000})
	second := ServiceID(1234, startedAt, "/opt/homebrew/bin/node", "node", []int{3000, 5173})

	if first != second {
		t.Fatalf("expected stable id regardless of port order, got %q and %q", first, second)
	}
}

func TestServiceIDChangesWhenPIDChanges(t *testing.T) {
	startedAt := time.Unix(1_700_000_000, 0)

	first := ServiceID(1234, startedAt, "/opt/homebrew/bin/node", "node", []int{3000})
	second := ServiceID(5678, startedAt, "/opt/homebrew/bin/node", "node", []int{3000})

	if first == second {
		t.Fatalf("expected id to change when pid changes, got %q", first)
	}
}

func TestServiceIDChangesWhenStartedAtChanges(t *testing.T) {
	firstStartedAt := time.Unix(1_700_000_000, 0)
	secondStartedAt := firstStartedAt.Add(time.Second)

	first := ServiceID(1234, firstStartedAt, "/opt/homebrew/bin/node", "node", []int{3000})
	second := ServiceID(1234, secondStartedAt, "/opt/homebrew/bin/node", "node", []int{3000})

	if first == second {
		t.Fatalf("expected id to change when start time changes, got %q", first)
	}
}

func TestServiceIDFallsBackToCommand(t *testing.T) {
	startedAt := time.Unix(1_700_000_000, 0)

	id := ServiceID(1234, startedAt, "", "node", []int{3000})

	if !strings.Contains(id, "node") {
		t.Fatalf("expected id to include command fallback, got %q", id)
	}
}
