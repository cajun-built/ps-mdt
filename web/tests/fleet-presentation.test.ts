import assert from "node:assert/strict";
import test from "node:test";
import type { FleetAsset, FleetPersonnel } from "../src/interfaces/IFleet.ts";
import { canAccessFleetMdt, fleetOperatorSummary } from "../src/utils/fleetPresentation.ts";

const asset = {
	id: 11,
	assetUuid: "fleet-11",
	agency: "brpd",
	catalogKey: "brpd_patrol",
	model: "police",
	vehicleClass: "patrol",
	fleetNumber: "1001",
	plate: "BR1001",
	homeMotorPool: "brpd_hq",
	status: "available",
	assignmentType: "general_pool",
	version: 1,
	lastOperator: {
		personnelId: 27,
		citizenid: "CID27",
		callsign: "204",
		badge: "BR204",
		status: "returned",
		checkoutAt: "2026-08-22 14:15:00",
		returnedAt: "2026-08-22 15:30:00",
	},
} satisfies FleetAsset;

const personnel: FleetPersonnel[] = [{
	id: 27,
	citizenid: "CID27",
	name: "Jane Doe",
	badge: "BR204",
	callsign: "204",
	rankName: "Police Officer",
	assignments: ["patrol"],
	certifications: [],
}];

test("Fleet MDT access requires its dedicated permission", () => {
	assert.equal(canAccessFleetMdt((permission) => permission === "fleet.view"), false);
	assert.equal(canAccessFleetMdt((permission) => permission === "fleet.mdt"), true);
});

test("returned fleet assets identify their last operator", () => {
	assert.deepEqual(fleetOperatorSummary(asset, personnel), {
		label: "Last operated by",
		operator: "Police Officer Jane Doe, Callsign 204",
		timestamp: "2026-08-22 15:30:00",
	});
});

test("active fleet assets identify their current operator", () => {
	const activeAsset: FleetAsset = {
		...asset,
		status: "checked_out",
		lastOperator: { ...asset.lastOperator, status: "active", returnedAt: undefined },
	};
	assert.deepEqual(fleetOperatorSummary(activeAsset, []), {
		label: "Currently operated by",
		operator: "Callsign 204",
		timestamp: "2026-08-22 14:15:00",
	});
});

test("unused fleet assets clearly report no operator", () => {
	assert.deepEqual(fleetOperatorSummary({ ...asset, lastOperator: undefined }, personnel), {
		label: "Last operated by",
		operator: "No recorded operator",
		timestamp: undefined,
	});
});
