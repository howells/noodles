package killer

import (
	"context"
	"errors"
	"fmt"
	"syscall"
	"time"
)

const DefaultGracePeriod = time.Second

type Signaler interface {
	Signal(ctx context.Context, target Target, signal Signal) error
	Alive(ctx context.Context, target Target) (bool, error)
}

type Waiter interface {
	Wait(ctx context.Context, duration time.Duration) error
}

type Executor struct {
	Signaler    Signaler
	Waiter      Waiter
	GracePeriod time.Duration
}

type KillResult struct {
	PlanSnapshotID string         `json:"planSnapshotId"`
	Targets        []TargetResult `json:"targets"`
	Exclusions     []Exclusion    `json:"exclusions"`
}

type TargetResult struct {
	ServiceID   string          `json:"serviceId"`
	PID         int             `json:"pid"`
	Success     bool            `json:"success"`
	Attempts    []SignalAttempt `json:"attempts"`
	ErrorReason string          `json:"errorReason,omitempty"`
}

type SignalAttempt struct {
	Signal  Signal `json:"signal"`
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}

func NewExecutor(signaler Signaler) *Executor {
	if signaler == nil {
		signaler = SystemSignaler{}
	}
	return &Executor{
		Signaler:    signaler,
		Waiter:      RealWaiter{},
		GracePeriod: DefaultGracePeriod,
	}
}

func (e *Executor) Execute(ctx context.Context, plan KillPlan) (KillResult, error) {
	if e.Signaler == nil {
		return KillResult{}, errors.New("missing signaler")
	}
	waiter := e.Waiter
	if waiter == nil {
		waiter = RealWaiter{}
	}
	gracePeriod := e.GracePeriod
	if gracePeriod == 0 {
		gracePeriod = DefaultGracePeriod
	}

	result := KillResult{
		PlanSnapshotID: plan.SnapshotID,
		Exclusions:     append([]Exclusion(nil), plan.Exclusions...),
		Targets:        make([]TargetResult, 0, len(plan.Targets)),
	}

	resultsByPID := make(map[int]int, len(plan.Targets))
	for _, target := range plan.Targets {
		targetResult := TargetResult{
			ServiceID: target.ServiceID,
			PID:       target.PID,
		}
		attempt := signalAttempt(ctx, e.Signaler, target, SignalTerm)
		targetResult.Attempts = append(targetResult.Attempts, attempt)
		if !attempt.Success {
			targetResult.ErrorReason = attempt.Error
		}
		resultsByPID[target.PID] = len(result.Targets)
		result.Targets = append(result.Targets, targetResult)
	}

	if err := waiter.Wait(ctx, gracePeriod); err != nil {
		return result, err
	}

	for _, target := range plan.Targets {
		index := resultsByPID[target.PID]
		targetResult := &result.Targets[index]
		alive, err := e.Signaler.Alive(ctx, target)
		if err != nil {
			targetResult.ErrorReason = err.Error()
			continue
		}
		if alive {
			attempt := signalAttempt(ctx, e.Signaler, target, SignalKill)
			targetResult.Attempts = append(targetResult.Attempts, attempt)
			if !attempt.Success {
				targetResult.ErrorReason = attempt.Error
				continue
			}
		}
		targetResult.Success = targetResult.ErrorReason == ""
	}

	return result, nil
}

func signalAttempt(ctx context.Context, signaler Signaler, target Target, signal Signal) SignalAttempt {
	err := signaler.Signal(ctx, target, signal)
	if err != nil {
		return SignalAttempt{
			Signal: signal,
			Error:  err.Error(),
		}
	}
	return SignalAttempt{
		Signal:  signal,
		Success: true,
	}
}

type RealWaiter struct{}

func (RealWaiter) Wait(ctx context.Context, duration time.Duration) error {
	timer := time.NewTimer(duration)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

type SystemSignaler struct{}

func (SystemSignaler) Signal(_ context.Context, target Target, signal Signal) error {
	syscallSignal, err := toSyscallSignal(signal)
	if err != nil {
		return err
	}
	pid := target.PID
	if target.ProcessGroupID > 0 {
		pid = -target.ProcessGroupID
	}
	return syscall.Kill(pid, syscallSignal)
}

func (SystemSignaler) Alive(_ context.Context, target Target) (bool, error) {
	err := syscall.Kill(target.PID, 0)
	if err == nil {
		return true, nil
	}
	if errors.Is(err, syscall.ESRCH) {
		return false, nil
	}
	return false, err
}

func toSyscallSignal(signal Signal) (syscall.Signal, error) {
	switch signal {
	case SignalTerm:
		return syscall.SIGTERM, nil
	case SignalKill:
		return syscall.SIGKILL, nil
	default:
		return 0, fmt.Errorf("unsupported signal %q", signal)
	}
}
