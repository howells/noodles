package desktop

import (
	"context"
	"errors"
	"testing"

	"github.com/howells/noodles/internal/app"
	"github.com/howells/noodles/internal/killer"
)

func TestServiceDelegatesScanToCore(t *testing.T) {
	core := &fakeCore{
		scanResult: app.Snapshot{ID: "snap-1"},
	}
	service := NewService(core)

	result, err := service.Scan(context.Background(), app.Query{Search: "materia"})
	if err != nil {
		t.Fatalf("Scan returned error: %v", err)
	}

	if result.ID != "snap-1" {
		t.Fatalf("expected delegated snapshot, got %#v", result)
	}
	if core.scanQuery.Search != "materia" {
		t.Fatalf("expected query to be delegated, got %#v", core.scanQuery)
	}
}

func TestServiceDelegatesKillToCore(t *testing.T) {
	core := &fakeCore{
		killResult: killer.KillResult{
			PlanSnapshotID: "snap-1",
		},
	}
	service := NewService(core)

	result, err := service.KillService(context.Background(), killer.KillRequest{ServiceID: "service-1"})
	if err != nil {
		t.Fatalf("KillService returned error: %v", err)
	}

	if result.PlanSnapshotID != "snap-1" {
		t.Fatalf("expected delegated kill result, got %#v", result)
	}
	if core.killRequest.ServiceID != "service-1" {
		t.Fatalf("expected request to be delegated, got %#v", core.killRequest)
	}
}

func TestServiceReturnsCoreErrors(t *testing.T) {
	scanErr := errors.New("scan failed")
	killErr := errors.New("kill failed")
	service := NewService(&fakeCore{scanErr: scanErr, killErr: killErr})

	if _, err := service.Scan(context.Background(), app.Query{}); !errors.Is(err, scanErr) {
		t.Fatalf("expected scan error, got %v", err)
	}
	if _, err := service.KillService(context.Background(), killer.KillRequest{ServiceID: "service-1"}); !errors.Is(err, killErr) {
		t.Fatalf("expected kill error, got %v", err)
	}
}

type fakeCore struct {
	scanQuery   app.Query
	scanResult  app.Snapshot
	scanErr     error
	killRequest killer.KillRequest
	killResult  killer.KillResult
	killErr     error
}

func (c *fakeCore) Scan(_ context.Context, query app.Query) (app.Snapshot, error) {
	c.scanQuery = query
	return c.scanResult, c.scanErr
}

func (c *fakeCore) KillService(_ context.Context, request killer.KillRequest) (killer.KillResult, error) {
	c.killRequest = request
	return c.killResult, c.killErr
}
