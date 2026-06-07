package app

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/howells/noodles/internal/classifier"
	"github.com/howells/noodles/internal/ports"
	"github.com/howells/noodles/internal/processes"
	"github.com/howells/noodles/internal/projects"
)

type ListenerCollector interface {
	Collect(ctx context.Context) ([]ports.Listener, error)
}

type ProcessCollector interface {
	Collect(ctx context.Context, pids []int) (map[int]processes.Process, error)
}

type ProjectResolver interface {
	Resolve(cwd string) (projects.Project, error)
}

type Scanner struct {
	listeners ListenerCollector
	processes ProcessCollector
	projects  ProjectResolver
	now       func() time.Time
}

func NewScanner(
	listeners ListenerCollector,
	processes ProcessCollector,
	projects ProjectResolver,
	now func() time.Time,
) *Scanner {
	if now == nil {
		now = time.Now
	}
	return &Scanner{
		listeners: listeners,
		processes: processes,
		projects:  projects,
		now:       now,
	}
}

func (s *Scanner) Scan(ctx context.Context, query Query) (Snapshot, error) {
	_ = query
	startedAt := s.now()
	listeners, err := s.listeners.Collect(ctx)
	if err != nil {
		return Snapshot{}, fmt.Errorf("collect listeners: %w", err)
	}

	pids := uniqueListenerPIDs(listeners)
	processTable, err := s.processes.Collect(ctx, pids)
	if err != nil {
		return Snapshot{}, fmt.Errorf("collect processes: %w", err)
	}

	listenersByPID := make(map[int][]ports.Listener)
	for _, listener := range listeners {
		listenersByPID[listener.PID] = append(listenersByPID[listener.PID], listener)
	}

	finishedAt := s.now()
	snapshotID := fmt.Sprintf("snapshot:%d", finishedAt.UnixNano())
	services := make([]Service, 0, len(listenersByPID))

	for pid, pidListeners := range listenersByPID {
		process, ok := processTable[pid]
		if !ok {
			continue
		}

		project, err := s.projects.Resolve(process.CWD)
		if err != nil {
			return Snapshot{}, fmt.Errorf("resolve project for pid %d: %w", pid, err)
		}

		portsForService := listenerPorts(pidListeners)
		classification := classifier.Classify(process.Command, process.CommandLine, process.CWD, parentCommands(processTable, pid))
		service := Service{
			ID:                  ServiceID(process.PID, process.StartedAt, process.ExecutablePath, process.Command, portsForService),
			SnapshotID:          snapshotID,
			PID:                 process.PID,
			ProcessGroupID:      process.ProcessGroupID,
			ParentPID:           process.ParentPID,
			Command:             process.Command,
			CommandLine:         process.CommandLine,
			ExecutablePath:      process.ExecutablePath,
			CWD:                 process.CWD,
			ProjectID:           project.ID,
			ProjectName:         project.Name,
			ProjectDisplayName:  project.DisplayName,
			ProjectRoot:         project.Root,
			WorkspaceRoot:       project.WorkspaceRoot,
			Ports:               portsForService,
			ResidentMemoryBytes: process.ResidentMemoryBytes,
			StartedAt:           process.StartedAt,
			AgeSeconds:          int64(finishedAt.Sub(process.StartedAt).Seconds()),
			SourceLabel:         classification.Label,
			SourceConfidence:    classification.Confidence,
			SourceEvidence:      classification.Evidence,
			Killable:            classification.Label != "system",
		}
		services = append(services, service)
	}

	sort.SliceStable(services, func(i, j int) bool {
		return services[i].PID < services[j].PID
	})

	snapshot := Snapshot{
		ID:       snapshotID,
		Services: services,
		Metadata: ScanMetadata{
			SnapshotID:           snapshotID,
			ScanStartedAt:        startedAt,
			ScanFinishedAt:       finishedAt,
			ScanDuration:         finishedAt.Sub(startedAt),
			ScanDurationMs:       finishedAt.Sub(startedAt).Milliseconds(),
			LastSuccessfulScanAt: finishedAt,
		},
	}

	return snapshot, nil
}

func uniqueListenerPIDs(listeners []ports.Listener) []int {
	seen := make(map[int]struct{})
	var pids []int
	for _, listener := range listeners {
		if _, exists := seen[listener.PID]; exists {
			continue
		}
		seen[listener.PID] = struct{}{}
		pids = append(pids, listener.PID)
	}
	sort.Ints(pids)
	return pids
}

func listenerPorts(listeners []ports.Listener) []int {
	seen := make(map[int]struct{})
	var result []int
	for _, listener := range listeners {
		if _, exists := seen[listener.Port]; exists {
			continue
		}
		seen[listener.Port] = struct{}{}
		result = append(result, listener.Port)
	}
	sort.Ints(result)
	return result
}

func parentCommands(processTable map[int]processes.Process, pid int) []string {
	parentPIDs := processes.ParentChain(processTable, pid)
	commands := make([]string, 0, len(parentPIDs))
	for _, parentPID := range parentPIDs {
		if process, ok := processTable[parentPID]; ok {
			commands = append(commands, process.Command)
		}
	}
	return commands
}
