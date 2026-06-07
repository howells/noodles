export namespace app {
	
	export class Group {
	    id: string;
	    label: string;
	    kind: string;
	    serviceIds: string[];
	    ports: number[];
	    totalResidentMemoryBytes: number;
	    killableServiceCount: number;
	    excludedServiceCount: number;
	    sourceLabels: string[];
	
	    static createFrom(source: any = {}) {
	        return new Group(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.label = source["label"];
	        this.kind = source["kind"];
	        this.serviceIds = source["serviceIds"];
	        this.ports = source["ports"];
	        this.totalResidentMemoryBytes = source["totalResidentMemoryBytes"];
	        this.killableServiceCount = source["killableServiceCount"];
	        this.excludedServiceCount = source["excludedServiceCount"];
	        this.sourceLabels = source["sourceLabels"];
	    }
	}
	export class Project {
	    id: string;
	    name: string;
	    displayName: string;
	    root: string;
	    workspaceRoot: string;
	    serviceCount: number;
	    totalResidentMemoryBytes: number;
	    ports: number[];
	    sourceLabels: string[];
	    killableServiceCount: number;
	    excludedServiceCount: number;
	
	    static createFrom(source: any = {}) {
	        return new Project(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.displayName = source["displayName"];
	        this.root = source["root"];
	        this.workspaceRoot = source["workspaceRoot"];
	        this.serviceCount = source["serviceCount"];
	        this.totalResidentMemoryBytes = source["totalResidentMemoryBytes"];
	        this.ports = source["ports"];
	        this.sourceLabels = source["sourceLabels"];
	        this.killableServiceCount = source["killableServiceCount"];
	        this.excludedServiceCount = source["excludedServiceCount"];
	    }
	}
	export class Query {
	    sortBy: string;
	    sortDirection: string;
	    groupBy: string;
	    search: string;
	    projectId: string;
	    sourceLabel: string;
	    port: number;
	    killableOnly: boolean;
	    hideSystem: boolean;
	    memoryThresholdBytes: number;
	
	    static createFrom(source: any = {}) {
	        return new Query(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.sortBy = source["sortBy"];
	        this.sortDirection = source["sortDirection"];
	        this.groupBy = source["groupBy"];
	        this.search = source["search"];
	        this.projectId = source["projectId"];
	        this.sourceLabel = source["sourceLabel"];
	        this.port = source["port"];
	        this.killableOnly = source["killableOnly"];
	        this.hideSystem = source["hideSystem"];
	        this.memoryThresholdBytes = source["memoryThresholdBytes"];
	    }
	}
	export class ScanMetadata {
	    snapshotId: string;
	    // Go type: time
	    scanStartedAt: any;
	    // Go type: time
	    scanFinishedAt: any;
	    scanDurationMs: number;
	    // Go type: time
	    lastSuccessfulScanAt: any;
	    scanSkippedReason?: string;
	    permissionWarnings?: string[];
	    scannerWarnings?: string[];
	
	    static createFrom(source: any = {}) {
	        return new ScanMetadata(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.snapshotId = source["snapshotId"];
	        this.scanStartedAt = this.convertValues(source["scanStartedAt"], null);
	        this.scanFinishedAt = this.convertValues(source["scanFinishedAt"], null);
	        this.scanDurationMs = source["scanDurationMs"];
	        this.lastSuccessfulScanAt = this.convertValues(source["lastSuccessfulScanAt"], null);
	        this.scanSkippedReason = source["scanSkippedReason"];
	        this.permissionWarnings = source["permissionWarnings"];
	        this.scannerWarnings = source["scannerWarnings"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Service {
	    id: string;
	    snapshotId: string;
	    pid: number;
	    processGroupId: number;
	    parentPid: number;
	    command: string;
	    commandLine: string;
	    executablePath: string;
	    cwd: string;
	    projectId: string;
	    projectName: string;
	    projectDisplayName: string;
	    projectRoot: string;
	    workspaceRoot: string;
	    ports: number[];
	    residentMemoryBytes: number;
	    memoryUnavailableReason?: string;
	    cpuPercent?: number;
	    cpuUnavailableReason?: string;
	    // Go type: time
	    startedAt: any;
	    ageSeconds: number;
	    sourceLabel: string;
	    sourceConfidence: string;
	    sourceEvidence: string[];
	    killable: boolean;
	    warnings: string[];
	
	    static createFrom(source: any = {}) {
	        return new Service(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.snapshotId = source["snapshotId"];
	        this.pid = source["pid"];
	        this.processGroupId = source["processGroupId"];
	        this.parentPid = source["parentPid"];
	        this.command = source["command"];
	        this.commandLine = source["commandLine"];
	        this.executablePath = source["executablePath"];
	        this.cwd = source["cwd"];
	        this.projectId = source["projectId"];
	        this.projectName = source["projectName"];
	        this.projectDisplayName = source["projectDisplayName"];
	        this.projectRoot = source["projectRoot"];
	        this.workspaceRoot = source["workspaceRoot"];
	        this.ports = source["ports"];
	        this.residentMemoryBytes = source["residentMemoryBytes"];
	        this.memoryUnavailableReason = source["memoryUnavailableReason"];
	        this.cpuPercent = source["cpuPercent"];
	        this.cpuUnavailableReason = source["cpuUnavailableReason"];
	        this.startedAt = this.convertValues(source["startedAt"], null);
	        this.ageSeconds = source["ageSeconds"];
	        this.sourceLabel = source["sourceLabel"];
	        this.sourceConfidence = source["sourceConfidence"];
	        this.sourceEvidence = source["sourceEvidence"];
	        this.killable = source["killable"];
	        this.warnings = source["warnings"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Snapshot {
	    id: string;
	    services: Service[];
	    projects: Project[];
	    groups: Group[];
	    metadata: ScanMetadata;
	
	    static createFrom(source: any = {}) {
	        return new Snapshot(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.services = this.convertValues(source["services"], Service);
	        this.projects = this.convertValues(source["projects"], Project);
	        this.groups = this.convertValues(source["groups"], Group);
	        this.metadata = this.convertValues(source["metadata"], ScanMetadata);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}

}

export namespace killer {
	
	export class Exclusion {
	    serviceId: string;
	    pid: number;
	    reason: string;
	
	    static createFrom(source: any = {}) {
	        return new Exclusion(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.serviceId = source["serviceId"];
	        this.pid = source["pid"];
	        this.reason = source["reason"];
	    }
	}
	export class KillRequest {
	    snapshotId: string;
	    serviceId?: string;
	    projectId?: string;
	    pid: number;
	    processGroupId: number;
	    // Go type: time
	    startedAt: any;
	    command: string;
	    executablePath: string;
	    cwd: string;
	    projectRoot: string;
	    expectedPorts: number[];
	    requestedAction: string;
	
	    static createFrom(source: any = {}) {
	        return new KillRequest(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.snapshotId = source["snapshotId"];
	        this.serviceId = source["serviceId"];
	        this.projectId = source["projectId"];
	        this.pid = source["pid"];
	        this.processGroupId = source["processGroupId"];
	        this.startedAt = this.convertValues(source["startedAt"], null);
	        this.command = source["command"];
	        this.executablePath = source["executablePath"];
	        this.cwd = source["cwd"];
	        this.projectRoot = source["projectRoot"];
	        this.expectedPorts = source["expectedPorts"];
	        this.requestedAction = source["requestedAction"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class SignalAttempt {
	    signal: string;
	    success: boolean;
	    error?: string;
	
	    static createFrom(source: any = {}) {
	        return new SignalAttempt(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.signal = source["signal"];
	        this.success = source["success"];
	        this.error = source["error"];
	    }
	}
	export class TargetResult {
	    serviceId: string;
	    pid: number;
	    success: boolean;
	    attempts: SignalAttempt[];
	    errorReason?: string;
	
	    static createFrom(source: any = {}) {
	        return new TargetResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.serviceId = source["serviceId"];
	        this.pid = source["pid"];
	        this.success = source["success"];
	        this.attempts = this.convertValues(source["attempts"], SignalAttempt);
	        this.errorReason = source["errorReason"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class KillResult {
	    planSnapshotId: string;
	    targets: TargetResult[];
	    exclusions: Exclusion[];
	
	    static createFrom(source: any = {}) {
	        return new KillResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.planSnapshotId = source["planSnapshotId"];
	        this.targets = this.convertValues(source["targets"], TargetResult);
	        this.exclusions = this.convertValues(source["exclusions"], Exclusion);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	

}

