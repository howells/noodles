package classifier

import (
	"testing"
)

func TestClassifyNextAsDevServer(t *testing.T) {
	got := Classify("node", "next dev --port 3000", "/Users/danielhowells/Sites/app", nil)

	assertClassification(t, got, "dev-server", "high")
	assertHasEvidence(t, got, "next")
}

func TestClassifyStorybook(t *testing.T) {
	got := Classify("node", "storybook dev -p 6006", "/Users/danielhowells/Sites/app", nil)

	assertClassification(t, got, "storybook", "high")
	assertHasEvidence(t, got, "storybook")
}

func TestClassifyAgentBrowser(t *testing.T) {
	got := Classify("agent-browser-darwin-arm64", "agent-browser-darwin-arm64 --port 54165", "/tmp", nil)

	assertClassification(t, got, "agent", "high")
	assertHasEvidence(t, got, "agent")
}

func TestClassifyBrowser(t *testing.T) {
	got := Classify("Google Chrome", "Google Chrome --remote-debugging-port=9222", "/Applications/Google Chrome.app", nil)

	assertClassification(t, got, "browser", "medium")
	assertHasEvidence(t, got, "Chrome")
}

func TestClassifyUnknownUnderUserSites(t *testing.T) {
	got := Classify("custom-tool", "custom-tool serve", "/Users/danielhowells/Sites/app", nil)

	assertClassification(t, got, "unknown", "low")
	assertHasEvidence(t, got, "/Users/")
}

func assertClassification(t *testing.T, got Classification, label string, confidence string) {
	t.Helper()
	if got.Label != label {
		t.Fatalf("expected label %q, got %+v", label, got)
	}
	if got.Confidence != confidence {
		t.Fatalf("expected confidence %q, got %+v", confidence, got)
	}
}

func assertHasEvidence(t *testing.T, got Classification, contains string) {
	t.Helper()
	for _, evidence := range got.Evidence {
		if containsText(evidence, contains) {
			return
		}
	}
	t.Fatalf("expected evidence containing %q, got %#v", contains, got.Evidence)
}

func containsText(value string, want string) bool {
	for i := 0; i+len(want) <= len(value); i++ {
		if value[i:i+len(want)] == want {
			return true
		}
	}
	return false
}
