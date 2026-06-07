package desktop

import (
	"context"
	"time"

	"github.com/howells/noodles/internal/app"
	"github.com/howells/noodles/internal/killer"
	"github.com/howells/noodles/internal/ports"
	"github.com/howells/noodles/internal/processes"
	"github.com/howells/noodles/internal/projects"
)

type productionCore struct {
	scanner  *app.Scanner
	executor *killer.Executor
}

func NewProductionService() *Service {
	return NewService(NewProductionCore())
}

func NewProductionCore() Core {
	return &productionCore{
		scanner: app.NewScanner(
			ports.NewCollector(nil),
			processes.NewCollector(nil, time.Now),
			projects.NewResolver(),
			time.Now,
		),
		executor: killer.NewExecutor(nil),
	}
}

func (c *productionCore) Scan(ctx context.Context, query app.Query) (app.Snapshot, error) {
	snapshot, err := c.scanner.Scan(ctx, query)
	if err != nil {
		return app.Snapshot{}, err
	}
	return snapshot, nil
}

func (c *productionCore) KillService(ctx context.Context, request killer.KillRequest) (killer.KillResult, error) {
	current, err := c.scanner.Scan(ctx, app.Query{})
	if err != nil {
		return killer.KillResult{}, err
	}
	plan, err := killer.BuildServiceKillPlan(request, current)
	if err != nil {
		return killer.KillResult{}, err
	}
	result, err := c.executor.Execute(ctx, plan)
	if err != nil {
		return result, err
	}
	return result, nil
}
