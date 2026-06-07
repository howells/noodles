package app

import (
	"fmt"
	"sort"
	"strings"
)

func BuildView(snapshot Snapshot, query Query) Snapshot {
	view := snapshot
	view.Services = filterServices(snapshot.Services, query)
	sortServices(view.Services, query)
	view.Projects = buildProjects(view.Services)
	view.Groups = buildGroups(view.Services, query.GroupBy)
	return view
}

func filterServices(services []Service, query Query) []Service {
	filtered := make([]Service, 0, len(services))
	for _, service := range services {
		if query.HideSystem && service.SourceLabel == "system" {
			continue
		}
		if query.KillableOnly && !service.Killable {
			continue
		}
		if query.ProjectID != "" && service.ProjectID != query.ProjectID {
			continue
		}
		if query.SourceLabel != "" && service.SourceLabel != query.SourceLabel {
			continue
		}
		if query.Port != 0 && !serviceHasPort(service, query.Port) {
			continue
		}
		if query.MemoryThresholdBytes != 0 && service.ResidentMemoryBytes < query.MemoryThresholdBytes {
			continue
		}
		if !matchesSearch(service, query.Search) {
			continue
		}
		filtered = append(filtered, copyService(service))
	}
	return filtered
}

func sortServices(services []Service, query Query) {
	sortBy := query.SortBy
	if sortBy == "" {
		sortBy = SortByMemory
	}
	direction := query.SortDirection
	if direction == "" {
		direction = defaultSortDirection(sortBy)
	}

	sort.SliceStable(services, func(i, j int) bool {
		comparison := compareServices(services[i], services[j], sortBy)
		if comparison != 0 && direction == SortDirectionDesc {
			return comparison > 0
		}
		if comparison != 0 {
			return comparison < 0
		}
		comparison = compareServiceTiebreakers(services[i], services[j])
		return comparison < 0
	})
}

func defaultSortDirection(sortBy SortBy) SortDirection {
	switch sortBy {
	case SortByProject, SortByProcess, SortBySource, SortByPort:
		return SortDirectionAsc
	default:
		return SortDirectionDesc
	}
}

func compareServices(a Service, b Service, sortBy SortBy) int {
	switch sortBy {
	case SortByCPU:
		return compareOptionalFloat(a.CPUPercent, b.CPUPercent)
	case SortByPort:
		return compareInts(lowestPort(a.Ports), lowestPort(b.Ports))
	case SortByAge:
		return compareInt64s(a.AgeSeconds, b.AgeSeconds)
	case SortByProject:
		return compareStrings(projectLabel(a), projectLabel(b))
	case SortByProcess:
		return compareStrings(a.Command, b.Command)
	case SortBySource:
		return compareStrings(a.SourceLabel, b.SourceLabel)
	case SortByMemory, "":
		return compareUint64s(a.ResidentMemoryBytes, b.ResidentMemoryBytes)
	default:
		return compareUint64s(a.ResidentMemoryBytes, b.ResidentMemoryBytes)
	}
}

func compareServiceTiebreakers(a Service, b Service) int {
	for _, comparison := range []int{
		compareUint64s(a.ResidentMemoryBytes, b.ResidentMemoryBytes),
		compareOptionalFloat(a.CPUPercent, b.CPUPercent),
		compareStrings(projectLabel(a), projectLabel(b)),
		compareInts(lowestPort(a.Ports), lowestPort(b.Ports)),
		compareStrings(a.Command, b.Command),
		compareInts(a.PID, b.PID),
		compareStrings(a.ID, b.ID),
	} {
		if comparison != 0 {
			return comparison
		}
	}
	return 0
}

func buildProjects(services []Service) []Project {
	projectsByID := make(map[string]*Project)
	for _, service := range services {
		id := service.ProjectID
		if id == "" {
			id = "unknown"
		}
		project := projectsByID[id]
		if project == nil {
			project = &Project{
				ID:            id,
				Name:          firstNonEmpty(service.ProjectName, service.ProjectDisplayName, id),
				DisplayName:   firstNonEmpty(service.ProjectDisplayName, service.ProjectName, id),
				Root:          service.ProjectRoot,
				WorkspaceRoot: service.WorkspaceRoot,
			}
			projectsByID[id] = project
		}
		project.ServiceCount++
		project.TotalResidentMemoryBytes += service.ResidentMemoryBytes
		if service.Killable {
			project.KillableServiceCount++
		} else {
			project.ExcludedServiceCount++
		}
		project.Ports = appendUniqueInts(project.Ports, service.Ports...)
		project.SourceLabels = appendUniqueStrings(project.SourceLabels, service.SourceLabel)
	}

	projects := make([]Project, 0, len(projectsByID))
	for _, project := range projectsByID {
		sort.Ints(project.Ports)
		sort.Strings(project.SourceLabels)
		projects = append(projects, *project)
	}
	sort.SliceStable(projects, func(i, j int) bool {
		if projects[i].TotalResidentMemoryBytes != projects[j].TotalResidentMemoryBytes {
			return projects[i].TotalResidentMemoryBytes > projects[j].TotalResidentMemoryBytes
		}
		return projects[i].DisplayName < projects[j].DisplayName
	})
	return projects
}

func buildGroups(services []Service, groupBy GroupBy) []Group {
	switch groupBy {
	case GroupByProject:
		return buildServiceGroups(services, func(service Service) (string, string, GroupBy) {
			id := service.ProjectID
			if id == "" {
				id = "unknown"
			}
			return id, projectLabel(service), GroupByProject
		})
	case GroupBySource:
		return buildServiceGroups(services, func(service Service) (string, string, GroupBy) {
			label := service.SourceLabel
			if label == "" {
				label = "unknown"
			}
			return label, label, GroupBySource
		})
	case GroupByPortRange:
		return buildServiceGroups(services, func(service Service) (string, string, GroupBy) {
			rangeID := portRangeLabel(lowestPort(service.Ports))
			return rangeID, rangeID, GroupByPortRange
		})
	case GroupByParentApp:
		return buildServiceGroups(services, func(service Service) (string, string, GroupBy) {
			id := fmt.Sprintf("ppid:%d", service.ParentPID)
			if service.ParentPID == 0 {
				id = "ppid:unknown"
			}
			return id, id, GroupByParentApp
		})
	default:
		return nil
	}
}

func buildServiceGroups(services []Service, groupKey func(Service) (string, string, GroupBy)) []Group {
	groupsByID := make(map[string]*Group)
	for _, service := range services {
		id, label, kind := groupKey(service)
		group := groupsByID[id]
		if group == nil {
			group = &Group{
				ID:    id,
				Label: label,
				Kind:  kind,
			}
			groupsByID[id] = group
		}
		group.ServiceIDs = append(group.ServiceIDs, service.ID)
		group.Ports = appendUniqueInts(group.Ports, service.Ports...)
		group.TotalResidentMemoryBytes += service.ResidentMemoryBytes
		if service.Killable {
			group.KillableServiceCount++
		} else {
			group.ExcludedServiceCount++
		}
		group.SourceLabels = appendUniqueStrings(group.SourceLabels, service.SourceLabel)
	}

	groups := make([]Group, 0, len(groupsByID))
	for _, group := range groupsByID {
		sort.Strings(group.ServiceIDs)
		sort.Ints(group.Ports)
		sort.Strings(group.SourceLabels)
		groups = append(groups, *group)
	}
	sort.SliceStable(groups, func(i, j int) bool {
		if groups[i].TotalResidentMemoryBytes != groups[j].TotalResidentMemoryBytes {
			return groups[i].TotalResidentMemoryBytes > groups[j].TotalResidentMemoryBytes
		}
		if groups[i].KillableServiceCount != groups[j].KillableServiceCount {
			return groups[i].KillableServiceCount > groups[j].KillableServiceCount
		}
		return groups[i].Label < groups[j].Label
	})
	return groups
}

func matchesSearch(service Service, search string) bool {
	needle := strings.ToLower(strings.TrimSpace(search))
	if needle == "" {
		return true
	}
	haystack := strings.ToLower(strings.Join([]string{
		service.ProjectDisplayName,
		service.ProjectName,
		service.ProjectID,
		service.ProjectRoot,
		service.WorkspaceRoot,
		service.CWD,
		service.Command,
		service.CommandLine,
		service.ExecutablePath,
		service.SourceLabel,
		portSearchText(service.Ports),
	}, " "))
	return strings.Contains(haystack, needle)
}

func portSearchText(ports []int) string {
	parts := make([]string, 0, len(ports))
	for _, port := range ports {
		parts = append(parts, fmt.Sprintf("%d", port))
	}
	return strings.Join(parts, " ")
}

func serviceHasPort(service Service, port int) bool {
	for _, candidate := range service.Ports {
		if candidate == port {
			return true
		}
	}
	return false
}

func copyService(service Service) Service {
	service.Ports = append([]int(nil), service.Ports...)
	service.SourceEvidence = append([]string(nil), service.SourceEvidence...)
	service.Warnings = append([]string(nil), service.Warnings...)
	return service
}

func projectLabel(service Service) string {
	return firstNonEmpty(service.ProjectDisplayName, service.ProjectName, service.ProjectID, "unknown")
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			return value
		}
	}
	return ""
}

func lowestPort(ports []int) int {
	if len(ports) == 0 {
		return 0
	}
	lowest := ports[0]
	for _, port := range ports[1:] {
		if port < lowest {
			lowest = port
		}
	}
	return lowest
}

func portRangeLabel(port int) string {
	switch {
	case port == 0:
		return "unknown"
	case port < 1024:
		return "0-1023"
	case port < 3000:
		return "1024-2999"
	case port < 6000:
		return "3000-5999"
	case port < 10000:
		return "6000-9999"
	default:
		return "10000+"
	}
}

func appendUniqueInts(values []int, additions ...int) []int {
	seen := make(map[int]struct{}, len(values)+len(additions))
	for _, value := range values {
		seen[value] = struct{}{}
	}
	for _, value := range additions {
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		values = append(values, value)
	}
	return values
}

func appendUniqueStrings(values []string, additions ...string) []string {
	seen := make(map[string]struct{}, len(values)+len(additions))
	for _, value := range values {
		seen[value] = struct{}{}
	}
	for _, value := range additions {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		values = append(values, value)
	}
	return values
}

func compareUint64s(a uint64, b uint64) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	default:
		return 0
	}
}

func compareOptionalFloat(a *float64, b *float64) int {
	switch {
	case a == nil && b == nil:
		return 0
	case a == nil:
		return -1
	case b == nil:
		return 1
	case *a < *b:
		return -1
	case *a > *b:
		return 1
	default:
		return 0
	}
}

func compareInts(a int, b int) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	default:
		return 0
	}
}

func compareInt64s(a int64, b int64) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	default:
		return 0
	}
}

func compareStrings(a string, b string) int {
	return strings.Compare(strings.ToLower(a), strings.ToLower(b))
}
