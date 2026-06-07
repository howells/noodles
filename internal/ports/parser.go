package ports

import (
	"fmt"
	"strconv"
	"strings"
)

type Listener struct {
	PID      int
	Command  string
	Address  string
	Port     int
	Protocol string
}

func ParseLsofListeners(output string) ([]Listener, error) {
	var listeners []Listener
	seen := make(map[string]struct{})
	currentPID := 0
	currentCommand := ""

	for _, rawLine := range strings.FieldsFunc(output, func(r rune) bool { return r == '\n' || r == '\r' }) {
		if rawLine == "" {
			continue
		}

		prefix := rawLine[0]
		value := rawLine[1:]

		switch prefix {
		case 'p':
			pid, err := strconv.Atoi(value)
			if err != nil {
				return nil, fmt.Errorf("parse lsof pid %q: %w", value, err)
			}
			currentPID = pid
		case 'c':
			currentCommand = value
		case 'n':
			if currentPID == 0 || currentCommand == "" {
				continue
			}
			address, port, ok := parseAddressAndPort(value)
			if !ok {
				continue
			}
			key := fmt.Sprintf("%d|%s|%d", currentPID, address, port)
			if _, exists := seen[key]; exists {
				continue
			}
			seen[key] = struct{}{}
			listeners = append(listeners, Listener{
				PID:      currentPID,
				Command:  currentCommand,
				Address:  address,
				Port:     port,
				Protocol: "tcp",
			})
		}
	}

	return listeners, nil
}

func parseAddressAndPort(name string) (string, int, bool) {
	colonIndex := strings.LastIndex(name, ":")
	if colonIndex == -1 || colonIndex == len(name)-1 {
		return "", 0, false
	}

	portPart := name[colonIndex+1:]
	digitEnd := 0
	for digitEnd < len(portPart) && portPart[digitEnd] >= '0' && portPart[digitEnd] <= '9' {
		digitEnd++
	}
	if digitEnd == 0 {
		return "", 0, false
	}

	port, err := strconv.Atoi(portPart[:digitEnd])
	if err != nil {
		return "", 0, false
	}

	return name[:colonIndex], port, true
}
