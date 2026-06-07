package ports

import (
	"context"
	"errors"
	"reflect"
	"testing"
)

type fakeRunner struct {
	command string
	args    []string
	output  string
	err     error
	calls   int
}

func (r *fakeRunner) Run(ctx context.Context, command string, args ...string) (string, error) {
	r.calls++
	r.command = command
	r.args = append([]string(nil), args...)
	return r.output, r.err
}

func TestCollectorRunsSingleAllListenersCommand(t *testing.T) {
	runner := &fakeRunner{output: "p1234\ncnode\nn*:3000\n"}
	collector := NewCollector(runner)

	listeners, err := collector.Collect(context.Background())
	if err != nil {
		t.Fatalf("Collect returned error: %v", err)
	}

	if runner.calls != 1 {
		t.Fatalf("expected runner to be called once, got %d", runner.calls)
	}
	if runner.command != "/usr/sbin/lsof" {
		t.Fatalf("unexpected command: %q", runner.command)
	}
	expectedArgs := []string{"-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"}
	if !reflect.DeepEqual(runner.args, expectedArgs) {
		t.Fatalf("unexpected args: got %#v want %#v", runner.args, expectedArgs)
	}
	if len(listeners) != 1 || listeners[0].Port != 3000 {
		t.Fatalf("unexpected listeners: %+v", listeners)
	}
}

func TestCollectorReturnsRunnerErrorWithContext(t *testing.T) {
	runner := &fakeRunner{err: errors.New("permission denied")}
	collector := NewCollector(runner)

	_, err := collector.Collect(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !errors.Is(err, runner.err) {
		t.Fatalf("expected wrapped runner error, got %v", err)
	}
}
