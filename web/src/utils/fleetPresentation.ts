import type { FleetAsset, FleetPersonnel } from "../interfaces/IFleet";

export function canAccessFleetMdt(hasPermission: (permission: string) => boolean): boolean {
	return hasPermission("fleet.mdt");
}

export function fleetOperatorSummary(
	asset: FleetAsset,
	personnel: FleetPersonnel[],
): { label: string; operator: string; timestamp?: string } {
	const operator = asset.lastOperator;
	if (!operator) {
		return { label: "Last operated by", operator: "No recorded operator", timestamp: undefined };
	}

	const member = personnel.find((person) => person.id === operator.personnelId);
	const callsign = member?.callsign || operator.callsign;
	let identity = member
		? `${member.rankName || "Officer"} ${member.name}`
		: callsign
			? `Callsign ${callsign}`
			: operator.badge
				? `Badge ${operator.badge}`
				: operator.citizenid;
	if (member && callsign) identity += `, Callsign ${callsign}`;

	const active = operator.status === "active";
	return {
		label: active ? "Currently operated by" : "Last operated by",
		operator: identity,
		timestamp: active ? operator.checkoutAt : operator.returnedAt || operator.checkoutAt,
	};
}
