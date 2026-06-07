package app

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

type Confidence string

const (
	ConfidenceLow    Confidence = "low"
	ConfidenceMedium Confidence = "medium"
	ConfidenceHigh   Confidence = "high"
)

type SortBy string

const (
	SortByMemory  SortBy = "memory"
	SortByCPU     SortBy = "cpu"
	SortByPort    SortBy = "port"
	SortByAge     SortBy = "age"
	SortByProject SortBy = "project"
	SortByProcess SortBy = "process"
	SortBySource  SortBy = "source"
)

type SortDirection string

const (
	SortDirectionAsc  SortDirection = "asc"
	SortDirectionDesc SortDirection = "desc"
)

type GroupBy string

const (
	GroupByNone      GroupBy = "none"
	GroupByProject   GroupBy = "project"
	GroupBySource    GroupBy = "source"
	GroupByPortRange GroupBy = "port-range"
	GroupByParentApp GroupBy = "parent-app"
)

type Query struct {
	SortBy               SortBy        `json:"sortBy"`
	SortDirection        SortDirection `json:"sortDirection"`
	GroupBy              GroupBy       `json:"groupBy"`
	Search               string        `json:"search"`
	ProjectID            string        `json:"projectId"`
	SourceLabel          string        `json:"sourceLabel"`
	Port                 int           `json:"port"`
	KillableOnly         bool          `json:"killableOnly"`
	HideSystem           bool          `json:"hideSystem"`
	MemoryThresholdBytes uint64        `json:"memoryThresholdBytes"`
}

type Service struct {
	ID                      string     `json:"id"`
	SnapshotID              string     `json:"snapshotId"`
	PID                     int        `json:"pid"`
	ProcessGroupID          int        `json:"processGroupId"`
	ParentPID               int        `json:"parentPid"`
	Command                 string     `json:"command"`
	CommandLine             string     `json:"commandLine"`
	ExecutablePath          string     `json:"executablePath"`
	CWD                     string     `json:"cwd"`
	ProjectID               string     `json:"projectId"`
	ProjectName             string     `json:"projectName"`
	ProjectDisplayName      string     `json:"projectDisplayName"`
	ProjectRoot             string     `json:"projectRoot"`
	WorkspaceRoot           string     `json:"workspaceRoot"`
	Ports                   []int      `json:"ports"`
	ResidentMemoryBytes     uint64     `json:"residentMemoryBytes"`
	MemoryUnavailableReason string     `json:"memoryUnavailableReason,omitempty"`
	CPUPercent              *float64   `json:"cpuPercent,omitempty"`
	CPUUnavailableReason    string     `json:"cpuUnavailableReason,omitempty"`
	StartedAt               time.Time  `json:"startedAt"`
	AgeSeconds              int64      `json:"ageSeconds"`
	SourceLabel             string     `json:"sourceLabel"`
	SourceConfidence        Confidence `json:"sourceConfidence"`
	SourceEvidence          []string   `json:"sourceEvidence"`
	Killable                bool       `json:"killable"`
	Warnings                []string   `json:"warnings"`
}

type Project struct {
	ID                       string   `json:"id"`
	Name                     string   `json:"name"`
	DisplayName              string   `json:"displayName"`
	Root                     string   `json:"root"`
	WorkspaceRoot            string   `json:"workspaceRoot"`
	ServiceCount             int      `json:"serviceCount"`
	TotalResidentMemoryBytes uint64   `json:"totalResidentMemoryBytes"`
	Ports                    []int    `json:"ports"`
	SourceLabels             []string `json:"sourceLabels"`
	KillableServiceCount     int      `json:"killableServiceCount"`
	ExcludedServiceCount     int      `json:"excludedServiceCount"`
}

type ScanMetadata struct {
	SnapshotID           string        `json:"snapshotId"`
	ScanStartedAt        time.Time     `json:"scanStartedAt"`
	ScanFinishedAt       time.Time     `json:"scanFinishedAt"`
	ScanDuration         time.Duration `json:"-"`
	ScanDurationMs       int64         `json:"scanDurationMs"`
	LastSuccessfulScanAt time.Time     `json:"lastSuccessfulScanAt"`
	ScanSkippedReason    string        `json:"scanSkippedReason,omitempty"`
	PermissionWarnings   []string      `json:"permissionWarnings,omitempty"`
	ScannerWarnings      []string      `json:"scannerWarnings,omitempty"`
}

type Snapshot struct {
	ID       string       `json:"id"`
	Services []Service    `json:"services"`
	Projects []Project    `json:"projects"`
	Groups   []Group      `json:"groups"`
	Metadata ScanMetadata `json:"metadata"`
}

type Group struct {
	ID                       string   `json:"id"`
	Label                    string   `json:"label"`
	Kind                     GroupBy  `json:"kind"`
	ServiceIDs               []string `json:"serviceIds"`
	Ports                    []int    `json:"ports"`
	TotalResidentMemoryBytes uint64   `json:"totalResidentMemoryBytes"`
	KillableServiceCount     int      `json:"killableServiceCount"`
	ExcludedServiceCount     int      `json:"excludedServiceCount"`
	SourceLabels             []string `json:"sourceLabels"`
}

func ServiceID(pid int, startedAt time.Time, executablePath string, command string, ports []int) string {
	identity := strings.TrimSpace(executablePath)
	if identity == "" {
		identity = strings.TrimSpace(command)
	}

	sortedPorts := append([]int(nil), ports...)
	sort.Ints(sortedPorts)

	portParts := make([]string, 0, len(sortedPorts))
	for _, port := range sortedPorts {
		portParts = append(portParts, fmt.Sprintf("%d", port))
	}

	return fmt.Sprintf("pid:%d|started:%d|identity:%s|ports:%s",
		pid,
		startedAt.UnixNano(),
		identity,
		strings.Join(portParts, ","),
	)
}
