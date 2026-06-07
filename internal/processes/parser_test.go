package processes

import (
	"testing"
	"time"
)

func TestParseProcessRowsConvertsRSSAndStartedAt(t *testing.T) {
	now := time.Unix(1_700_000_100, 0)
	rows := "1234\t100\t1234\t2048\t100\tnode\tnode server.js\n"

	processes, err := ParseProcessRows(rows, now)
	if err != nil {
		t.Fatalf("ParseProcessRows returned error: %v", err)
	}

	got := processes[1234]
	if got.PID != 1234 {
		t.Fatalf("expected pid 1234, got %+v", got)
	}
	if got.ResidentMemoryBytes != 2048*1024 {
		t.Fatalf("expected rss bytes, got %d", got.ResidentMemoryBytes)
	}
	if !got.StartedAt.Equal(now.Add(-100 * time.Second)) {
		t.Fatalf("expected startedAt derived from etimes, got %s", got.StartedAt)
	}
}

func TestParseProcessRowsPreservesCommandAndArgs(t *testing.T) {
	now := time.Unix(1_700_000_100, 0)
	rows := "1234\t100\t1234\t2048\t100\tnode\tnode /Users/danielhowells/Sites/app/server.js --port 3000\n"

	processes, err := ParseProcessRows(rows, now)
	if err != nil {
		t.Fatalf("ParseProcessRows returned error: %v", err)
	}

	got := processes[1234]
	if got.Command != "node" {
		t.Fatalf("expected command node, got %q", got.Command)
	}
	if got.CommandLine != "node /Users/danielhowells/Sites/app/server.js --port 3000" {
		t.Fatalf("unexpected command line: %q", got.CommandLine)
	}
}

func TestParseProcessRowsReturnsUsefulErrorForMalformedRows(t *testing.T) {
	now := time.Unix(1_700_000_100, 0)

	_, err := ParseProcessRows("not-enough-fields\n", now)
	if err == nil {
		t.Fatal("expected error")
	}
}
