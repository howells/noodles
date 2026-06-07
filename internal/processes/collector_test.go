package processes

import (
	"context"
	"testing"
	"time"
)

func TestCollectorCollectsCandidateAndParentProcesses(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"/bin/ps -ww -p 10 -o pid= -o ppid= -o pgid= -o rss= -o etime= -o comm= -o args=": "10 5 10 2048 01:00 node node server.js\n",
			"/bin/ps -ww -p 5 -o pid= -o ppid= -o pgid= -o rss= -o etime= -o comm= -o args=":  "5 1 5 1024 02:00 zsh /bin/zsh\n",
			"/usr/sbin/lsof -a -p 10 -d cwd -Fn":                                              "p10\nn/Users/danielhowells/Sites/materia\n",
			"/usr/sbin/lsof -a -p 5 -d cwd -Fn":                                               "p5\nn/Users/danielhowells\n",
		},
	}
	collector := NewCollector(runner, func() time.Time { return time.Unix(1_700_000_100, 0) })

	table, err := collector.Collect(context.Background(), []int{10})
	if err != nil {
		t.Fatalf("Collect returned error: %v", err)
	}

	if _, ok := table[10]; !ok {
		t.Fatalf("expected candidate process, got %#v", table)
	}
	if _, ok := table[5]; !ok {
		t.Fatalf("expected parent process, got %#v", table)
	}
	if table[10].CWD != "/Users/danielhowells/Sites/materia" {
		t.Fatalf("expected cwd enrichment, got %#v", table[10])
	}
}

func TestParseElapsedSupportsMacOSEtimeFormats(t *testing.T) {
	for _, tc := range []struct {
		value string
		want  int
	}{
		{value: "42", want: 42},
		{value: "01:02", want: 62},
		{value: "02:03:04", want: 7384},
		{value: "1-02:03:04", want: 93784},
	} {
		got, err := parseElapsed(tc.value)
		if err != nil {
			t.Fatalf("parseElapsed(%q) returned error: %v", tc.value, err)
		}
		if got != tc.want {
			t.Fatalf("parseElapsed(%q) = %d, want %d", tc.value, got, tc.want)
		}
	}
}

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

type fakeRunner struct {
	outputs map[string]string
}

func (r *fakeRunner) Run(_ context.Context, command string, args ...string) (string, error) {
	key := command
	for _, arg := range args {
		key += " " + arg
	}
	return r.outputs[key], nil
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
