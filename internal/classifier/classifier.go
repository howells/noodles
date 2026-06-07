package classifier

import (
	"strings"
)

type Classification struct {
	Label      string
	Confidence string
	Evidence   []string
}

func Classify(command string, commandLine string, cwd string, parentCommands []string) Classification {
	commandText := strings.ToLower(command)
	commandLineText := strings.ToLower(commandLine)
	parentText := strings.ToLower(strings.Join(parentCommands, " "))

	if strings.Contains(commandLineText, "storybook") {
		return Classification{
			Label:      "storybook",
			Confidence: "high",
			Evidence:   []string{"command line contains storybook"},
		}
	}

	if containsAny(commandLineText, "next dev", "vite", "tsx", "webpack-dev-server") || containsAny(commandText, "vite", "next") {
		return Classification{
			Label:      "dev-server",
			Confidence: "high",
			Evidence:   []string{"command or command line matches dev server: next/vite/tsx"},
		}
	}

	if containsAny(commandText, "agent-browser", "codex", "claude") || containsAny(commandLineText, "agent-browser", "codex", "claude") || containsAny(parentText, "codex", "claude") {
		return Classification{
			Label:      "agent",
			Confidence: "high",
			Evidence:   []string{"command or parent chain contains agent marker"},
		}
	}

	if containsAny(commandText, "chrome", "safari", "firefox") || containsAny(commandLineText, "chrome", "safari", "firefox") {
		return Classification{
			Label:      "browser",
			Confidence: "medium",
			Evidence:   []string{"command contains Chrome/Safari/Firefox browser marker"},
		}
	}

	if containsAny(commandText, "node", "bun", "deno", "npm", "pnpm", "yarn") {
		return Classification{
			Label:      "node-tool",
			Confidence: "medium",
			Evidence:   []string{"command matches JavaScript runtime or package manager"},
		}
	}

	if containsAny(commandText, "controlcenter", "launchd", "rapportd") {
		return Classification{
			Label:      "system",
			Confidence: "medium",
			Evidence:   []string{"command matches known system process"},
		}
	}

	evidence := []string{"no known command marker"}
	if strings.Contains(cwd, "/Users/") {
		evidence = append(evidence, "cwd is under /Users/")
	}

	return Classification{
		Label:      "unknown",
		Confidence: "low",
		Evidence:   evidence,
	}
}

func containsAny(value string, needles ...string) bool {
	for _, needle := range needles {
		if strings.Contains(value, needle) {
			return true
		}
	}
	return false
}
