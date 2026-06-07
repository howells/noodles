package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/howells/noodles/internal/app"
	"github.com/howells/noodles/internal/desktop"
	"github.com/howells/noodles/internal/killer"
)

type client interface {
	Scan(ctx context.Context, query app.Query) (app.Snapshot, error)
	KillService(ctx context.Context, request killer.KillRequest) (killer.KillResult, error)
}

type ProjectSelection struct {
	Project app.Project
}

type AmbiguousProjectError struct {
	Name           string
	CandidateRoots []string
}

func (e *AmbiguousProjectError) Error() string {
	return fmt.Sprintf("project %q is ambiguous: %s", e.Name, strings.Join(e.CandidateRoots, ", "))
}

func main() {
	if err := run(context.Background(), desktop.NewProductionService(), os.Stdout, os.Stderr, os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(ctx context.Context, core client, stdout io.Writer, stderr io.Writer, args []string) error {
	if len(args) == 0 {
		return errors.New("usage: noodles list|kill")
	}

	switch args[0] {
	case "list":
		return runList(ctx, core, stdout, args[1:])
	case "kill":
		return runKill(ctx, core, stdout, args[1:])
	default:
		fmt.Fprintf(stderr, "unknown command: %s\n", args[0])
		return errors.New("usage: noodles list|kill")
	}
}

func runList(ctx context.Context, core client, stdout io.Writer, args []string) error {
	flags := flag.NewFlagSet("list", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	sortBy := flags.String("sort", "", "sort field")
	if err := flags.Parse(args); err != nil {
		return err
	}

	query := app.Query{SortBy: parseSortBy(*sortBy)}
	snapshot, err := core.Scan(ctx, query)
	if err != nil {
		return err
	}

	fmt.Fprintln(stdout, "PROJECT\tPORTS\tMEMORY\tCOMMAND\tSOURCE")
	for _, service := range snapshot.Services {
		fmt.Fprintf(stdout,
			"%s\t%s\t%s\t%s\t%s\n",
			serviceProjectLabel(service),
			formatPorts(service.Ports),
			formatBytes(service.ResidentMemoryBytes),
			service.Command,
			service.SourceLabel,
		)
	}
	return nil
}

func runKill(ctx context.Context, core client, stdout io.Writer, args []string) error {
	flags := flag.NewFlagSet("kill", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	projectRoot := flags.String("project-root", "", "project root")
	projectName := flags.String("project", "", "project name")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if strings.TrimSpace(*projectRoot) == "" && strings.TrimSpace(*projectName) == "" {
		return errors.New("kill requires --project-root or --project")
	}

	snapshot, err := core.Scan(ctx, app.Query{})
	if err != nil {
		return err
	}
	selection, err := SelectProject(snapshot, *projectName, *projectRoot)
	if err != nil {
		return err
	}
	result, err := core.KillService(ctx, killer.KillRequest{
		ProjectID:       selection.Project.ID,
		ProjectRoot:     selection.Project.Root,
		RequestedAction: killer.KillActionProject,
	})
	if err != nil {
		return err
	}
	fmt.Fprintf(stdout, "kill targets: %d\n", len(result.Targets))
	return nil
}

func SelectProject(snapshot app.Snapshot, projectName string, projectRoot string) (ProjectSelection, error) {
	projectRoot = strings.TrimSpace(projectRoot)
	if projectRoot != "" {
		for _, project := range snapshot.Projects {
			if project.Root == projectRoot {
				return ProjectSelection{Project: project}, nil
			}
		}
		return ProjectSelection{}, fmt.Errorf("project root not found: %s", projectRoot)
	}

	projectName = strings.TrimSpace(projectName)
	if projectName == "" {
		return ProjectSelection{}, errors.New("project name is required")
	}

	var matches []app.Project
	for _, project := range snapshot.Projects {
		if project.DisplayName == projectName || project.Name == projectName {
			matches = append(matches, project)
		}
	}
	if len(matches) == 0 {
		return ProjectSelection{}, fmt.Errorf("project not found: %s", projectName)
	}
	if len(matches) > 1 {
		roots := make([]string, 0, len(matches))
		for _, project := range matches {
			roots = append(roots, project.Root)
		}
		sort.Strings(roots)
		return ProjectSelection{}, &AmbiguousProjectError{
			Name:           projectName,
			CandidateRoots: roots,
		}
	}
	return ProjectSelection{Project: matches[0]}, nil
}

func parseSortBy(value string) app.SortBy {
	switch app.SortBy(strings.TrimSpace(value)) {
	case app.SortByMemory:
		return app.SortByMemory
	case app.SortByCPU:
		return app.SortByCPU
	case app.SortByPort:
		return app.SortByPort
	case app.SortByAge:
		return app.SortByAge
	case app.SortByProject:
		return app.SortByProject
	case app.SortByProcess:
		return app.SortByProcess
	case app.SortBySource:
		return app.SortBySource
	default:
		return ""
	}
}

func serviceProjectLabel(service app.Service) string {
	for _, value := range []string{service.ProjectDisplayName, service.ProjectName, service.ProjectRoot, service.CWD, "unknown"} {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return "unknown"
}

func formatPorts(ports []int) string {
	if len(ports) == 0 {
		return "-"
	}
	sortedPorts := append([]int(nil), ports...)
	sort.Ints(sortedPorts)
	parts := make([]string, 0, len(sortedPorts))
	for _, port := range sortedPorts {
		parts = append(parts, fmt.Sprintf("%d", port))
	}
	return strings.Join(parts, ",")
}

func formatBytes(bytes uint64) string {
	const mb = 1024 * 1024
	return fmt.Sprintf("%.1f MB", float64(bytes)/mb)
}
