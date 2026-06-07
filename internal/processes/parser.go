package processes

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

func ParseProcessRows(output string, now time.Time) (map[int]Process, error) {
	result := make(map[int]Process)

	for lineNumber, rawLine := range strings.FieldsFunc(output, func(r rune) bool { return r == '\n' || r == '\r' }) {
		if strings.TrimSpace(rawLine) == "" {
			continue
		}

		fields := strings.SplitN(rawLine, "\t", 7)
		if len(fields) != 7 {
			return nil, fmt.Errorf("parse process row %d: expected 7 tab-separated fields, got %d", lineNumber+1, len(fields))
		}

		pid, err := parseIntField("pid", fields[0])
		if err != nil {
			return nil, fmt.Errorf("parse process row %d: %w", lineNumber+1, err)
		}
		parentPID, err := parseIntField("ppid", fields[1])
		if err != nil {
			return nil, fmt.Errorf("parse process row %d: %w", lineNumber+1, err)
		}
		processGroupID, err := parseIntField("pgid", fields[2])
		if err != nil {
			return nil, fmt.Errorf("parse process row %d: %w", lineNumber+1, err)
		}
		rssKB, err := parseUintField("rss", fields[3])
		if err != nil {
			return nil, fmt.Errorf("parse process row %d: %w", lineNumber+1, err)
		}
		elapsedSeconds, err := parseIntField("etimes", fields[4])
		if err != nil {
			return nil, fmt.Errorf("parse process row %d: %w", lineNumber+1, err)
		}

		result[pid] = Process{
			PID:                 pid,
			ParentPID:           parentPID,
			ProcessGroupID:      processGroupID,
			Command:             fields[5],
			CommandLine:         fields[6],
			ResidentMemoryBytes: rssKB * 1024,
			StartedAt:           now.Add(-time.Duration(elapsedSeconds) * time.Second),
		}
	}

	return result, nil
}

func parseIntField(name string, value string) (int, error) {
	parsed, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil {
		return 0, fmt.Errorf("%s %q: %w", name, value, err)
	}
	return parsed, nil
}

func parseUintField(name string, value string) (uint64, error) {
	parsed, err := strconv.ParseUint(strings.TrimSpace(value), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("%s %q: %w", name, value, err)
	}
	return parsed, nil
}
