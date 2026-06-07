package processes

import (
	"context"
	"fmt"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"
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
	now    func() time.Time
}

func NewCollector(runner CommandRunner, now func() time.Time) *Collector {
	if runner == nil {
		runner = ExecRunner{}
	}
	if now == nil {
		now = time.Now
	}
	return &Collector{runner: runner, now: now}
}

func (c *Collector) Collect(ctx context.Context, pids []int) (map[int]Process, error) {
	table := make(map[int]Process)
	queue := uniquePIDs(pids)
	seen := make(map[int]struct{}, len(queue))

	for depth := 0; len(queue) > 0 && depth < 32; depth++ {
		current := queue[0]
		queue = queue[1:]
		if _, exists := seen[current]; exists || current <= 0 {
			continue
		}
		seen[current] = struct{}{}

		process, err := c.collectOne(ctx, current)
		if err != nil {
			continue
		}
		table[process.PID] = process
		if process.ParentPID > 0 {
			if _, exists := seen[process.ParentPID]; !exists {
				queue = append(queue, process.ParentPID)
			}
		}
	}

	return table, nil
}

func (c *Collector) collectOne(ctx context.Context, pid int) (Process, error) {
	output, err := c.runner.Run(ctx, "/bin/ps", "-ww", "-p", strconv.Itoa(pid), "-o", "pid=", "-o", "ppid=", "-o", "pgid=", "-o", "rss=", "-o", "etime=", "-o", "comm=", "-o", "args=")
	if err != nil {
		return Process{}, fmt.Errorf("collect process %d: %w", pid, err)
	}

	processes, err := parsePSOutput(output, c.now())
	if err != nil {
		return Process{}, err
	}
	process, ok := processes[pid]
	if !ok {
		return Process{}, fmt.Errorf("process %d not found", pid)
	}
	process.CWD = c.collectCWD(ctx, pid)
	process.ExecutablePath = process.Command
	return process, nil
}

func (c *Collector) collectCWD(ctx context.Context, pid int) string {
	output, err := c.runner.Run(ctx, "/usr/sbin/lsof", "-a", "-p", strconv.Itoa(pid), "-d", "cwd", "-Fn")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(output, "\n") {
		if strings.HasPrefix(line, "n") {
			return strings.TrimSpace(strings.TrimPrefix(line, "n"))
		}
	}
	return ""
}

func parsePSOutput(output string, now time.Time) (map[int]Process, error) {
	result := make(map[int]Process)
	for lineNumber, rawLine := range strings.FieldsFunc(output, func(r rune) bool { return r == '\n' || r == '\r' }) {
		line := strings.TrimSpace(rawLine)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 7 {
			return nil, fmt.Errorf("parse ps row %d: expected at least 7 fields, got %d", lineNumber+1, len(fields))
		}
		pid, err := strconv.Atoi(fields[0])
		if err != nil {
			return nil, fmt.Errorf("parse ps row %d pid: %w", lineNumber+1, err)
		}
		ppid, err := strconv.Atoi(fields[1])
		if err != nil {
			return nil, fmt.Errorf("parse ps row %d ppid: %w", lineNumber+1, err)
		}
		pgid, err := strconv.Atoi(fields[2])
		if err != nil {
			return nil, fmt.Errorf("parse ps row %d pgid: %w", lineNumber+1, err)
		}
		rssKB, err := strconv.ParseUint(fields[3], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("parse ps row %d rss: %w", lineNumber+1, err)
		}
		elapsedSeconds, err := parseElapsed(fields[4])
		if err != nil {
			return nil, fmt.Errorf("parse ps row %d etime: %w", lineNumber+1, err)
		}
		result[pid] = Process{
			PID:                 pid,
			ParentPID:           ppid,
			ProcessGroupID:      pgid,
			Command:             fields[5],
			CommandLine:         strings.Join(fields[6:], " "),
			ResidentMemoryBytes: rssKB * 1024,
			StartedAt:           now.Add(-time.Duration(elapsedSeconds) * time.Second),
		}
	}
	return result, nil
}

func parseElapsed(value string) (int, error) {
	if seconds, err := strconv.Atoi(value); err == nil {
		return seconds, nil
	}

	dayParts := strings.Split(value, "-")
	days := 0
	timePart := value
	if len(dayParts) == 2 {
		parsedDays, err := strconv.Atoi(dayParts[0])
		if err != nil {
			return 0, err
		}
		days = parsedDays
		timePart = dayParts[1]
	}

	parts := strings.Split(timePart, ":")
	total := days * 24 * 60 * 60
	switch len(parts) {
	case 2:
		minutes, err := strconv.Atoi(parts[0])
		if err != nil {
			return 0, err
		}
		seconds, err := strconv.Atoi(parts[1])
		if err != nil {
			return 0, err
		}
		return total + minutes*60 + seconds, nil
	case 3:
		hours, err := strconv.Atoi(parts[0])
		if err != nil {
			return 0, err
		}
		minutes, err := strconv.Atoi(parts[1])
		if err != nil {
			return 0, err
		}
		seconds, err := strconv.Atoi(parts[2])
		if err != nil {
			return 0, err
		}
		return total + hours*60*60 + minutes*60 + seconds, nil
	default:
		return 0, fmt.Errorf("unsupported elapsed time %q", value)
	}
}

func uniquePIDs(pids []int) []int {
	seen := make(map[int]struct{}, len(pids))
	result := make([]int, 0, len(pids))
	for _, pid := range pids {
		if _, exists := seen[pid]; exists || pid <= 0 {
			continue
		}
		seen[pid] = struct{}{}
		result = append(result, pid)
	}
	sort.Ints(result)
	return result
}

func ParentChain(processes map[int]Process, pid int) []int {
	var chain []int
	seen := map[int]struct{}{pid: {}}
	current := pid

	for {
		process, exists := processes[current]
		if !exists || process.ParentPID <= 0 {
			return chain
		}

		parent, parentExists := processes[process.ParentPID]
		if !parentExists {
			return chain
		}

		if _, cycle := seen[parent.PID]; cycle {
			return chain
		}

		chain = append(chain, parent.PID)
		seen[parent.PID] = struct{}{}
		current = parent.PID
	}
}
