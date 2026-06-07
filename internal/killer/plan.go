package killer

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/howells/noodles/internal/app"
)

var (
	ErrMissingServiceID = errors.New("missing service id")
	ErrServiceNotFound  = errors.New("service not found")
	ErrStaleIdentity    = errors.New("stale service identity")
)

type KillAction string

const (
	KillActionService KillAction = "service"
	KillActionProject KillAction = "project"
)

type Signal string

const (
	SignalTerm Signal = "SIGTERM"
	SignalKill Signal = "SIGKILL"
)

type KillRequest struct {
	SnapshotID      string     `json:"snapshotId"`
	ServiceID       string     `json:"serviceId,omitempty"`
	ProjectID       string     `json:"projectId,omitempty"`
	PID             int        `json:"pid"`
	ProcessGroupID  int        `json:"processGroupId"`
	StartedAt       time.Time  `json:"startedAt"`
	Command         string     `json:"command"`
	ExecutablePath  string     `json:"executablePath"`
	CWD             string     `json:"cwd"`
	ProjectRoot     string     `json:"projectRoot"`
	ExpectedPorts   []int      `json:"expectedPorts"`
	RequestedAction KillAction `json:"requestedAction"`
}

type KillPlan struct {
	Request    KillRequest `json:"request"`
	SnapshotID string      `json:"snapshotId"`
	Targets    []Target    `json:"targets"`
	Exclusions []Exclusion `json:"exclusions"`
}

type Target struct {
	ServiceID      string   `json:"serviceId"`
	PID            int      `json:"pid"`
	ProcessGroupID int      `json:"processGroupId"`
	SignalOrder    []Signal `json:"signalOrder"`
	Reason         string   `json:"reason"`
}

type Exclusion struct {
	ServiceID string `json:"serviceId"`
	PID       int    `json:"pid"`
	Reason    string `json:"reason"`
}

func BuildServiceKillPlan(request KillRequest, current app.Snapshot) (KillPlan, error) {
	plan := KillPlan{
		Request:    copyKillRequest(request),
		SnapshotID: current.ID,
	}
	if strings.TrimSpace(request.ServiceID) == "" {
		return plan, ErrMissingServiceID
	}

	service, ok := findService(current.Services, request.ServiceID)
	if !ok {
		return plan, fmt.Errorf("%w: %s", ErrServiceNotFound, request.ServiceID)
	}

	if err := revalidateServiceIdentity(request, current, service); err != nil {
		return plan, err
	}

	if !service.Killable {
		plan.Exclusions = append(plan.Exclusions, Exclusion{
			ServiceID: service.ID,
			PID:       service.PID,
			Reason:    exclusionReason(service),
		})
		return plan, nil
	}

	plan.Targets = append(plan.Targets, Target{
		ServiceID:      service.ID,
		PID:            service.PID,
		ProcessGroupID: service.ProcessGroupID,
		SignalOrder:    []Signal{SignalTerm, SignalKill},
		Reason:         "selected service process tree",
	})
	return plan, nil
}

func revalidateServiceIdentity(request KillRequest, current app.Snapshot, service app.Service) error {
	if request.SnapshotID != "" && request.SnapshotID != current.ID && request.SnapshotID != service.SnapshotID {
		return stale("snapshot changed")
	}
	if service.SnapshotID != "" && request.SnapshotID != "" && service.SnapshotID != request.SnapshotID {
		return stale("service snapshot changed")
	}
	if request.PID != service.PID {
		return stale("pid changed")
	}
	if request.ProcessGroupID != service.ProcessGroupID {
		return stale("process group changed")
	}
	if !request.StartedAt.Equal(service.StartedAt) {
		return stale("start time changed")
	}
	if normalizedIdentity(request.ExecutablePath, request.Command) != normalizedIdentity(service.ExecutablePath, service.Command) {
		return stale("command identity changed")
	}
	if request.CWD != service.CWD {
		return stale("cwd changed")
	}
	if request.ProjectRoot != service.ProjectRoot {
		return stale("project root changed")
	}
	if !equalPortSets(request.ExpectedPorts, service.Ports) {
		return stale("ports changed")
	}
	return nil
}

func findService(services []app.Service, serviceID string) (app.Service, bool) {
	for _, service := range services {
		if service.ID == serviceID {
			return service, true
		}
	}
	return app.Service{}, false
}

func stale(reason string) error {
	return fmt.Errorf("%w: %s", ErrStaleIdentity, reason)
}

func normalizedIdentity(executablePath string, command string) string {
	if strings.TrimSpace(executablePath) != "" {
		return strings.TrimSpace(executablePath)
	}
	return strings.TrimSpace(command)
}

func equalPortSets(a []int, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	sortedA := append([]int(nil), a...)
	sortedB := append([]int(nil), b...)
	sort.Ints(sortedA)
	sort.Ints(sortedB)
	for i := range sortedA {
		if sortedA[i] != sortedB[i] {
			return false
		}
	}
	return true
}

func copyKillRequest(request KillRequest) KillRequest {
	request.ExpectedPorts = append([]int(nil), request.ExpectedPorts...)
	return request
}

func exclusionReason(service app.Service) string {
	if strings.TrimSpace(service.SourceLabel) != "" {
		return fmt.Sprintf("service is not killable: %s", service.SourceLabel)
	}
	return "service is not killable"
}
