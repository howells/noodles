package ports

import (
	"context"
	"fmt"
	"os/exec"
)

type CommandRunner interface {
	Run(ctx context.Context, command string, args ...string) (string, error)
}

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, command string, args ...string) (string, error) {
	output, err := exec.CommandContext(ctx, command, args...).Output()
	if err != nil {
		return "", err
	}
	return string(output), nil
}

type Collector struct {
	runner CommandRunner
}

func NewCollector(runner CommandRunner) *Collector {
	if runner == nil {
		runner = ExecRunner{}
	}
	return &Collector{runner: runner}
}

func (c *Collector) Collect(ctx context.Context) ([]Listener, error) {
	output, err := c.runner.Run(ctx, "/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn")
	if err != nil {
		return nil, fmt.Errorf("collect tcp listeners: %w", err)
	}

	listeners, err := ParseLsofListeners(output)
	if err != nil {
		return nil, fmt.Errorf("parse tcp listeners: %w", err)
	}
	return listeners, nil
}
