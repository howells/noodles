package processes

import "testing"

func TestParentChainReturnsParentsFromChildToRoot(t *testing.T) {
	table := map[int]Process{
		10: {PID: 10, ParentPID: 5},
		5:  {PID: 5, ParentPID: 2},
		2:  {PID: 2, ParentPID: 1},
		1:  {PID: 1, ParentPID: 0},
	}

	got := ParentChain(table, 10)
	want := []int{5, 2, 1}

	if !equalInts(got, want) {
		t.Fatalf("ParentChain() = %#v, want %#v", got, want)
	}
}

func TestParentChainStopsOnCycle(t *testing.T) {
	table := map[int]Process{
		10: {PID: 10, ParentPID: 5},
		5:  {PID: 5, ParentPID: 10},
	}

	got := ParentChain(table, 10)
	want := []int{5}

	if !equalInts(got, want) {
		t.Fatalf("ParentChain() = %#v, want %#v", got, want)
	}
}

func TestParentChainStopsOnMissingParent(t *testing.T) {
	table := map[int]Process{
		10: {PID: 10, ParentPID: 999},
	}

	got := ParentChain(table, 10)
	if len(got) != 0 {
		t.Fatalf("expected missing parent to stop traversal, got %#v", got)
	}
}

func equalInts(a []int, b []int) bool {
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
