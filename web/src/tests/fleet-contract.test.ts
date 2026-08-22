import type { FleetAsset, FleetBootstrap, FleetMutationResponse } from "../interfaces/IFleet";
import { NUI_EVENTS } from "../constants/nuiEvents";
import { isFleetAttention } from "../utils/fleetStatus";

const asset: FleetAsset = {
	id: 1,
	assetUuid: "asset-1",
	agency: "brpd",
	catalogKey: "brpd_patrol",
	model: "police",
	vehicleClass: "patrol",
	fleetNumber: "1201",
	plate: "BR1201",
	homeMotorPool: "brpd_hq",
	status: "available",
	assignmentType: "general_pool",
	maintenanceStatus: "service_required",
	serviceDue: true,
	canCheckout: true,
	version: 1,
};

const bootstrap: FleetBootstrap = {
	agency: "brpd",
	permissions: { "fleet.view": true },
	catalog: [],
	motorPools: [],
	personnel: [],
	assets: [asset],
	presets: {},
};

const response: FleetMutationResponse<FleetAsset> = { success: true, data: asset };

void bootstrap;
void response;
void NUI_EVENTS.FLEET.GET_BOOTSTRAP;
void isFleetAttention(asset);
