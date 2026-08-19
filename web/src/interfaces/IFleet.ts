export type FleetStatus =
	| "available"
	| "checked_out"
	| "reserved"
	| "out_of_service"
	| "recovery_pending"
	| "retired";

export type FleetAssignmentType =
	| "officer"
	| "general_pool"
	| "training_pool"
	| "command_pool"
	| "unit";

export interface FleetAsset {
	id: number;
	assetUuid: string;
	agency: string;
	catalogKey: string;
	model: string;
	vehicleClass: string;
	fleetNumber: string;
	plate: string;
	homeMotorPool: string;
	status: FleetStatus;
	assignmentType: FleetAssignmentType;
	assignedPersonnelId?: number;
	assignmentKey?: string;
	requiredPermission?: string;
	requiredCertification?: string;
	livery?: number;
	fuel?: number;
	engineHealth?: number;
	bodyHealth?: number;
	mileage?: number;
	version: number;
	canCheckout?: boolean;
	denialReason?: string;
}

export interface FleetCatalogEntry {
	key: string;
	model: string;
	label: string;
	vehicleClass: string;
	livery: number;
	presetKeys: string[];
	requiredPermission?: string;
	requiredAssignment?: string;
	requiredCertification?: string;
	motorPoolType: "ground" | "air" | "marine";
}

export interface FleetMotorPool {
	key: string;
	label: string;
	type: "ground" | "air" | "marine";
}

export interface FleetPersonnel {
	id: number;
	citizenid: string;
	name: string;
	badge?: string;
	callsign?: string;
	rankName?: string;
	assignments: string[];
	certifications: string[];
}

export interface FleetPreset {
	label: string;
	extras?: Record<string, boolean>;
	properties?: Record<string, unknown>;
}

export interface FleetBootstrap {
	agency: string;
	permissions: Record<string, boolean>;
	catalog: FleetCatalogEntry[];
	motorPools: FleetMotorPool[];
	personnel: FleetPersonnel[];
	assets: FleetAsset[];
	presets: Record<string, FleetPreset>;
}

export interface FleetMutationResponse<T = unknown> {
	success: boolean;
	reason?: string;
	data?: T;
}

export interface FleetCommissionPayload {
	actionId: string;
	catalogKey: string;
	motorPool: string;
	fleetNumber: string;
	plate: string;
	assignmentType: FleetAssignmentType;
	assignedPersonnelId?: number;
	assignmentKey?: string;
	presetKey: string;
	reason: string;
}
