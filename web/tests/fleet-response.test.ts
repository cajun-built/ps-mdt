import assert from "node:assert/strict";
import test from "node:test";

import {
	fleetFailureLabel,
	normalizeFleetResponse,
} from "../src/utils/fleetResponse.ts";

test("valid Fleet responses keep their server payload", () => {
	const data = { agency: "brpd", assets: [] };
	assert.deepEqual(normalizeFleetResponse({ success: true, data }), {
		success: true,
		data,
	});
	assert.deepEqual(
		normalizeFleetResponse({ success: false, reason: "off_duty" }),
		{ success: false, reason: "off_duty" },
	);
});

test("malformed Fleet responses receive a specific diagnostic reason", () => {
	assert.deepEqual(normalizeFleetResponse({}), {
		success: false,
		reason: "invalid_response",
	});
	assert.deepEqual(normalizeFleetResponse("unexpected response"), {
		success: false,
		reason: "invalid_response",
	});
	assert.deepEqual(normalizeFleetResponse({ success: false }), {
		success: false,
		reason: "missing_failure_reason",
	});
	assert.deepEqual(normalizeFleetResponse({ success: true }, true), {
		success: false,
		reason: "missing_bootstrap_data",
	});
});

test("Fleet diagnostic reasons are understandable in game", () => {
	assert.equal(
		fleetFailureLabel("invalid_response"),
		"Fleet service returned an invalid response. Check F8 for the diagnostic.",
	);
	assert.equal(
		fleetFailureLabel("missing_failure_reason"),
		"Fleet request was denied without a reason. Check F8 for the diagnostic.",
	);
	assert.equal(
		fleetFailureLabel("service_unavailable"),
		"Fleet services are currently unavailable",
	);
});
