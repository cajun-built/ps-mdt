import type { FleetAsset } from "../interfaces/IFleet";

export function isFleetAttention(asset: FleetAsset): boolean {
	return asset.status === "recovery_pending"
		|| asset.status === "out_of_service"
		|| asset.serviceDue === true;
}
