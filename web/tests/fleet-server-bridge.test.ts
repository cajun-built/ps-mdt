import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const fleetBridgeSource = readFileSync(
	new URL("../../server/backend/fleet.lua", import.meta.url),
	"utf8",
);
const fleetClientBridgeSource = readFileSync(
	new URL("../../client/backend/fleet.lua", import.meta.url),
	"utf8",
);

test("Fleet dynamic exports preserve the FiveM exports receiver", () => {
	assert.match(
		fleetBridgeSource,
		/\[exportName\]\(exports\.cgn_leo_fleet,\s*source,\s*payload\)/,
	);
});

test("Fleet NUI requests use the fleet service's collision safe callbacks", () => {
	assert.doesNotMatch(fleetClientBridgeSource, /ps\.callback\(/);
	assert.match(fleetClientBridgeSource, /lib\.callback\.await\(/);
	assert.match(fleetClientBridgeSource, /cgn_leo_fleet:server:getBootstrap/);
	assert.match(fleetClientBridgeSource, /cgn_leo_fleet:server:commission/);
	assert.match(fleetClientBridgeSource, /cgn_leo_fleet:server:assign/);
	assert.match(fleetClientBridgeSource, /cgn_leo_fleet:server:setStatus/);
	assert.match(fleetClientBridgeSource, /cgn_leo_fleet:server:renumber/);
});
