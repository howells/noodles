package processes

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
