package desktop

import (
	"context"
	"errors"
	"fmt"

	"github.com/howells/noodles/internal/app"
	"github.com/howells/noodles/internal/killer"
)

type Core interface {
	Scan(ctx context.Context, query app.Query) (app.Snapshot, error)
	KillService(ctx context.Context, request killer.KillRequest) (killer.KillResult, error)
}

type Service struct {
	core Core
}

func NewService(core Core) *Service {
	return &Service{core: core}
}

func (s *Service) Scan(ctx context.Context, query app.Query) (app.Snapshot, error) {
	if s.core == nil {
		return app.Snapshot{}, errors.New("desktop core is not configured")
	}
	return s.core.Scan(contextOrBackground(ctx), query)
}

func (s *Service) KillService(ctx context.Context, request killer.KillRequest) (killer.KillResult, error) {
	if s.core == nil {
		return killer.KillResult{}, errors.New("desktop core is not configured")
	}
	return s.core.KillService(contextOrBackground(ctx), request)
}

type UnavailableCore struct {
	Reason string
}

func NewUnavailableCore(reason string) UnavailableCore {
	return UnavailableCore{Reason: reason}
}

func (c UnavailableCore) Scan(context.Context, app.Query) (app.Snapshot, error) {
	return app.Snapshot{}, c.err()
}

func (c UnavailableCore) KillService(context.Context, killer.KillRequest) (killer.KillResult, error) {
	return killer.KillResult{}, c.err()
}

func (c UnavailableCore) err() error {
	if c.Reason == "" {
		return errors.New("desktop core is not configured")
	}
	return fmt.Errorf("desktop core is not configured: %s", c.Reason)
}

func contextOrBackground(ctx context.Context) context.Context {
	if ctx == nil {
		return context.Background()
	}
	return ctx
}
