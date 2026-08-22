import assert from "node:assert/strict";
import test from "node:test";

import * as rosterManagement from "../src/utils/rosterManagement.ts";

const { getPromotionActionState, personnelActionMessage } = rosterManagement;

test("server ID input accepts the numeric value produced by a number field", () => {
	const normalizeServerIdInput = rosterManagement.normalizeServerIdInput;
	assert.equal(typeof normalizeServerIdInput, "function");
	assert.equal(normalizeServerIdInput?.(24), "24");
	assert.equal(normalizeServerIdInput?.(" 24 "), "24");
});

test("promotion action explains each required step", () => {
	assert.deepEqual(getPromotionActionState(null, "", undefined, false, false), {
		disabled: true,
		label: "Select a Rank",
		hint: "Select the officer's new rank.",
	});

	assert.deepEqual(getPromotionActionState(4, "", "Sergeant", false, false), {
		disabled: true,
		label: "Set Rank to Sergeant",
		hint: "Enter a written reason of at least 3 characters.",
	});

	assert.deepEqual(getPromotionActionState(4, "Promotion approved", "Sergeant", false, false), {
		disabled: false,
		label: "Set Rank to Sergeant",
		hint: "Ready to update this officer's rank.",
	});
});

test("promotion action remains disabled while ranks load or a save is running", () => {
	assert.equal(getPromotionActionState(null, "", undefined, false, true).label, "Loading Ranks...");
	assert.equal(getPromotionActionState(4, "Promotion approved", "Sergeant", true, false).label, "Updating Rank...");
	assert.equal(getPromotionActionState(4, "Promotion approved", "Sergeant", true, false).disabled, true);
});

test("personnel denial codes are readable and actionable", () => {
	assert.equal(
		personnelActionMessage("assignment_required"),
		"Personnel assignment required. Another authorized command member or an administrator must grant it.",
	);
	assert.equal(
		personnelActionMessage("target_rank_denied"),
		"You can only change the rank of officers below you, and the new rank must remain below yours.",
	);
	assert.equal(personnelActionMessage("unexpected_backend_code"), "unexpected_backend_code");
});

test("rank requests are serialized while unrelated roster data loads concurrently", async () => {
	assert.equal(typeof rosterManagement.loadRosterManagementData, "function");

	const events: string[] = [];
	let activeRankRequests = 0;
	let maximumActiveRankRequests = 0;

	const loadRank = async (name: string) => {
		events.push(`${name}:start`);
		activeRankRequests += 1;
		maximumActiveRankRequests = Math.max(maximumActiveRankRequests, activeRankRequests);
		await Promise.resolve();
		activeRankRequests -= 1;
		events.push(`${name}:end`);
	};

	await rosterManagement.loadRosterManagementData(
		async () => {
			events.push("tags:start");
			await Promise.resolve();
			events.push("tags:end");
		},
		() => loadRank("current-ranks"),
		() => loadRank("transfer-ranks"),
	);

	assert.equal(maximumActiveRankRequests, 1);
	assert.ok(events.indexOf("tags:start") < events.indexOf("current-ranks:end"));
	assert.ok(events.indexOf("current-ranks:end") < events.indexOf("transfer-ranks:start"));
});
