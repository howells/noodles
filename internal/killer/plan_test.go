package killer

import (
	"errors"
	"testing"
	"time"

	"github.com/howells/noodles/internal/app"
)

func TestBuildServiceKillPlanCreatesTargetWithEscalationOrder(t *testing.T) {
	service := killableServiceFixture()
	snapshot := app.Snapshot{ID: "snap-1", Services: []app.Service{service}}

	plan, err := BuildServiceKillPlan(requestFromService(service), snapshot)
	if err != nil {
		t.Fatalf("BuildServiceKillPlan returned error: %v", err)
	}

	if len(plan.Targets) != 1 {
		t.Fatalf("expected one target, got %#v", plan.Targets)
	}
	target := plan.Targets[0]
	if target.PID != service.PID || target.ProcessGroupID != service.ProcessGroupID {
		t.Fatalf("unexpected target: %#v", target)
	}
	if len(target.SignalOrder) != 2 || target.SignalOrder[0] != SignalTerm || target.SignalOrder[1] != SignalKill {
		t.Fatalf("expected SIGTERM then SIGKILL, got %#v", target.SignalOrder)
	}
}

func TestBuildServiceKillPlanRejectsReusedPIDWithDifferentStartedAt(t *testing.T) {
	service := killableServiceFixture()
	snapshot := app.Snapshot{ID: "snap-1", Services: []app.Service{service}}
	request := requestFromService(service)
	request.StartedAt = request.StartedAt.Add(-time.Minute)

	plan, err := BuildServiceKillPlan(request, snapshot)
	if !errors.Is(err, ErrStaleIdentity) {
		t.Fatalf("expected stale identity error, got plan %#v and error %v", plan, err)
	}
	if len(plan.Targets) != 0 {
		t.Fatalf("stale identity should not include targets, got %#v", plan.Targets)
	}
}

func TestBuildServiceKillPlanAllowsFreshSnapshotWhenIdentityMatches(t *testing.T) {
	service := killableServiceFixture()
	fresh := service
	fresh.SnapshotID = "snap-2"
	snapshot := app.Snapshot{ID: "snap-2", Services: []app.Service{fresh}}

	plan, err := BuildServiceKillPlan(requestFromService(service), snapshot)
	if err != nil {
		t.Fatalf("BuildServiceKillPlan returned error: %v", err)
	}
	if len(plan.Targets) != 1 {
		t.Fatalf("expected target from matching fresh identity, got %#v", plan.Targets)
	}
}

func TestBuildServiceKillPlanRejectsChangedPorts(t *testing.T) {
	service := killableServiceFixture()
	snapshot := app.Snapshot{ID: "snap-1", Services: []app.Service{service}}
	request := requestFromService(service)
	request.ExpectedPorts = []int{3001}

	plan, err := BuildServiceKillPlan(request, snapshot)
	if !errors.Is(err, ErrStaleIdentity) {
		t.Fatalf("expected stale identity error, got plan %#v and error %v", plan, err)
	}
	if len(plan.Targets) != 0 {
		t.Fatalf("changed ports should not include targets, got %#v", plan.Targets)
	}
}

func TestBuildServiceKillPlanRejectsMissingServiceID(t *testing.T) {
	service := killableServiceFixture()
	snapshot := app.Snapshot{ID: "snap-1", Services: []app.Service{service}}
	request := requestFromService(service)
	request.ServiceID = ""

	plan, err := BuildServiceKillPlan(request, snapshot)
	if !errors.Is(err, ErrMissingServiceID) {
		t.Fatalf("expected missing service id error, got plan %#v and error %v", plan, err)
	}
	if len(plan.Targets) != 0 {
		t.Fatalf("missing service id should not include targets, got %#v", plan.Targets)
	}
}

func TestBuildServiceKillPlanExcludesNonKillableServiceWithReason(t *testing.T) {
	service := killableServiceFixture()
	service.Killable = false
	service.SourceLabel = "system"
	snapshot := app.Snapshot{ID: "snap-1", Services: []app.Service{service}}

	plan, err := BuildServiceKillPlan(requestFromService(service), snapshot)
	if err != nil {
		t.Fatalf("BuildServiceKillPlan returned error: %v", err)
	}
	if len(plan.Targets) != 0 {
		t.Fatalf("non-killable service should not include targets, got %#v", plan.Targets)
	}
	if len(plan.Exclusions) != 1 || plan.Exclusions[0].Reason == "" {
		t.Fatalf("expected exclusion reason, got %#v", plan.Exclusions)
	}
}

func killableServiceFixture() app.Service {
	return app.Service{
		ID:                 "service-1",
		SnapshotID:         "snap-1",
		PID:                1234,
		ProcessGroupID:     1234,
		Command:            "node",
		CommandLine:        "node server.js",
		ExecutablePath:     "/usr/local/bin/node",
		CWD:                "/Users/danielhowells/Sites/materia",
		ProjectID:          "project:materia",
		ProjectName:        "materia",
		ProjectDisplayName: "materia",
		ProjectRoot:        "/Users/danielhowells/Sites/materia",
		Ports:              []int{5173, 3000},
		StartedAt:          time.Unix(1_700_000_000, 0),
		SourceLabel:        "dev-server",
		Killable:           true,
	}
}

func requestFromService(service app.Service) KillRequest {
	return KillRequest{
		SnapshotID:      service.SnapshotID,
		ServiceID:       service.ID,
		PID:             service.PID,
		ProcessGroupID:  service.ProcessGroupID,
		StartedAt:       service.StartedAt,
		Command:         service.Command,
		ExecutablePath:  service.ExecutablePath,
		CWD:             service.CWD,
		ProjectRoot:     service.ProjectRoot,
		ExpectedPorts:   append([]int(nil), service.Ports...),
		RequestedAction: KillActionService,
	}
}
