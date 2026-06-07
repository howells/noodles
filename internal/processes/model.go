package processes

import "time"

type Process struct {
	PID                 int
	ParentPID           int
	ProcessGroupID      int
	Command             string
	CommandLine         string
	CWD                 string
	ExecutablePath      string
	ResidentMemoryBytes uint64
	CPUTimeSeconds      float64
	StartedAt           time.Time
}
