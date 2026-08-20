import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const rosterSource = readFileSync(
	new URL("../../server/backend/roster.lua", import.meta.url),
	"utf8",
);

test("authenticated MDT users can load agency rank definitions", () => {
	const callbackStart = rosterSource.indexOf(
		"ps.registerCallback('ps-mdt:server:getJobGrades'",
	);
	const callbackEnd = rosterSource.indexOf(
		"-- Promote/demote an officer",
		callbackStart,
	);
	const callbackSource = rosterSource.slice(callbackStart, callbackEnd);

	assert.ok(callbackStart >= 0, "getJobGrades callback is missing");
	assert.ok(callbackEnd > callbackStart, "getJobGrades callback boundary is missing");
	assert.doesNotMatch(
		callbackSource,
		/CheckPermission\(src, 'roster_manage_/,
		"rank definitions must not disappear because of a second permission lookup",
	);
	assert.match(callbackSource, /normalizeAgencyJobName\(payload\.job\)/);
	assert.match(callbackSource, /ps\.getSharedJob\(agencyKey\)/);
});
