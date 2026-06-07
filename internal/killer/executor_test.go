package killer

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestExecutorAttemptsSIGTERMFirst(t *testing.T) {
	signaler := &fakeSignaler{alive: map[int]bool{1234: false}}
	waiter := &fakeWaiter{}
	executor := NewExecutor(signaler)
	executor.Waiter = waiter

	result, err := executor.Execute(context.Background(), planWithTargets(targetFixture(1234), targetFixture(5678)))
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if got := signaler.calls[0]; got.PID != 1234 || got.Signal != SignalTerm {
		t.Fatalf("expected first signal to be SIGTERM for first target, got %#v", got)
	}
	if got := signaler.calls[1]; got.PID != 5678 || got.Signal != SignalTerm {
		t.Fatalf("expected second signal to be SIGTERM for second target, got %#v", got)
	}
	if waiter.waits != 1 {
		t.Fatalf("expected one grace wait, got %d", waiter.waits)
	}
	if len(result.Targets) != 2 {
		t.Fatalf("expected per-target results, got %#v", result.Targets)
	}
}

func TestExecutorSendsSIGKILLOnlyForTargetsStillAlive(t *testing.T) {
	signaler := &fakeSignaler{alive: map[int]bool{
		1234: false,
		5678: true,
	}}
	executor := NewExecutor(signaler)
	executor.Waiter = &fakeWaiter{}

	result, err := executor.Execute(context.Background(), planWithTargets(targetFixture(1234), targetFixture(5678)))
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if countSignal(signaler.calls, SignalKill) != 1 {
		t.Fatalf("expected one SIGKILL attempt, got %#v", signaler.calls)
	}
	if last := signaler.calls[len(signaler.calls)-1]; last.PID != 5678 || last.Signal != SignalKill {
		t.Fatalf("expected SIGKILL for still-alive target, got %#v", last)
	}
	if !resultForPID(result, 1234).Success {
		t.Fatalf("expected stopped target to succeed, got %#v", resultForPID(result, 1234))
	}
	if !resultForPID(result, 5678).Success {
		t.Fatalf("expected killed target to succeed, got %#v", resultForPID(result, 5678))
	}
}

func TestExecutorReportsPerTargetFailureWithoutStoppingOtherTargets(t *testing.T) {
	signaler := &fakeSignaler{
		alive: map[int]bool{
			1234: true,
			5678: false,
		},
		failures: map[signalCall]error{
			{PID: 1234, Signal: SignalTerm}: errors.New("permission denied"),
		},
	}
	executor := NewExecutor(signaler)
	executor.Waiter = &fakeWaiter{}

	result, err := executor.Execute(context.Background(), planWithTargets(targetFixture(1234), targetFixture(5678)))
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	failed := resultForPID(result, 1234)
	if failed.Success || failed.ErrorReason == "" {
		t.Fatalf("expected first target failure, got %#v", failed)
	}
	succeeded := resultForPID(result, 5678)
	if !succeeded.Success {
		t.Fatalf("expected second target to succeed despite first failure, got %#v", succeeded)
	}
}

func planWithTargets(targets ...Target) KillPlan {
	return KillPlan{
		SnapshotID: "snap-1",
		Targets:    targets,
	}
}

func targetFixture(pid int) Target {
	return Target{
		ServiceID:      "service",
		PID:            pid,
		ProcessGroupID: pid,
		SignalOrder:    []Signal{SignalTerm, SignalKill},
		Reason:         "test target",
	}
}

type signalCall struct {
	PID    int
	Signal Signal
}

type fakeSignaler struct {
	calls    []signalCall
	alive    map[int]bool
	failures map[signalCall]error
}

func (s *fakeSignaler) Signal(_ context.Context, target Target, signal Signal) error {
	call := signalCall{PID: target.PID, Signal: signal}
	s.calls = append(s.calls, call)
	if s.failures == nil {
		return nil
	}
	return s.failures[call]
}

func (s *fakeSignaler) Alive(_ context.Context, target Target) (bool, error) {
	return s.alive[target.PID], nil
}

type fakeWaiter struct {
	waits int
}

func (w *fakeWaiter) Wait(_ context.Context, _ time.Duration) error {
	w.waits++
	return nil
}

func countSignal(calls []signalCall, signal Signal) int {
	count := 0
	for _, call := range calls {
		if call.Signal == signal {
			count++
		}
	}
	return count
}

func resultForPID(result KillResult, pid int) TargetResult {
	for _, target := range result.Targets {
		if target.PID == pid {
			return target
		}
	}
	return TargetResult{}
}
