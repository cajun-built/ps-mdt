import assert from "node:assert/strict";
import test from "node:test";

import {
	getPromotionActionState,
	personnelActionMessage,
} from "../src/utils/rosterManagement.ts";

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
