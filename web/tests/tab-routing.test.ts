import assert from "node:assert/strict";
import test from "node:test";

import { MDT_TABS } from "../src/constants/index.ts";
import { SECURITY_CONFIG } from "../src/config/security.ts";

test("every visible MDT navigation tab is accepted by the tab router", () => {
	const rejectedTabs = MDT_TABS
		.map((tab) => tab.name)
		.filter(
			(tab) =>
				!(SECURITY_CONFIG.ALLOWED_TABS as readonly string[]).includes(tab),
		);

	assert.deepEqual(rejectedTabs, []);
});
