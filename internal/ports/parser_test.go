package ports

import "testing"

func TestParseLsofListenersParsesSingleNodeListener(t *testing.T) {
	output := "p1234\ncnode\nn*:3000\n"

	listeners, err := ParseLsofListeners(output)
	if err != nil {
		t.Fatalf("ParseLsofListeners returned error: %v", err)
	}

	if len(listeners) != 1 {
		t.Fatalf("expected 1 listener, got %d", len(listeners))
	}
	if listeners[0].PID != 1234 || listeners[0].Command != "node" || listeners[0].Address != "*" || listeners[0].Port != 3000 {
		t.Fatalf("unexpected listener: %+v", listeners[0])
	}
}

func TestParseLsofListenersParsesIPv6Listener(t *testing.T) {
	output := "p1234\ncvite\nn[::1]:5173\n"

	listeners, err := ParseLsofListeners(output)
	if err != nil {
		t.Fatalf("ParseLsofListeners returned error: %v", err)
	}

	if len(listeners) != 1 {
		t.Fatalf("expected 1 listener, got %d", len(listeners))
	}
	if listeners[0].Address != "[::1]" || listeners[0].Port != 5173 {
		t.Fatalf("expected IPv6 listener, got %+v", listeners[0])
	}
}

func TestParseLsofListenersIncludesHighPorts(t *testing.T) {
	output := "p5678\ncnode\nn*:30000\n"

	listeners, err := ParseLsofListeners(output)
	if err != nil {
		t.Fatalf("ParseLsofListeners returned error: %v", err)
	}

	if len(listeners) != 1 {
		t.Fatalf("expected 1 listener, got %d", len(listeners))
	}
	if listeners[0].Port != 30000 {
		t.Fatalf("expected port 30000, got %+v", listeners[0])
	}
}

func TestParseLsofListenersDeduplicatesSamePIDPortAndAddress(t *testing.T) {
	output := "p1234\ncnode\nn127.0.0.1:3000\nn127.0.0.1:3000\n"

	listeners, err := ParseLsofListeners(output)
	if err != nil {
		t.Fatalf("ParseLsofListeners returned error: %v", err)
	}

	if len(listeners) != 1 {
		t.Fatalf("expected duplicate listener to be removed, got %d", len(listeners))
	}
}

func TestParseLsofListenersDoesNotFilterNonNodeCommands(t *testing.T) {
	output := "p111\ncControlCenter\nn*:5000\n"

	listeners, err := ParseLsofListeners(output)
	if err != nil {
		t.Fatalf("ParseLsofListeners returned error: %v", err)
	}

	if len(listeners) != 1 {
		t.Fatalf("expected non-node listener to be parsed, got %d", len(listeners))
	}
	if listeners[0].Command != "ControlCenter" {
		t.Fatalf("expected command to be preserved, got %+v", listeners[0])
	}
}
