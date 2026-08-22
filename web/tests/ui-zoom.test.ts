import assert from "node:assert/strict";
import test from "node:test";

const uiZoom = await import("../src/utils/uiZoom.ts").catch(() => ({}));

test("the MDT defaults to a readable 130 percent interface scale", () => {
	assert.equal(uiZoom.DEFAULT_UI_ZOOM, 130);
	assert.deepEqual(uiZoom.getUiZoomLayout?.(130), {
		zoom: "130%",
		width: "100%",
		height: "100%",
	});
});

test("saved interface scale is validated before it is applied", () => {
	assert.equal(uiZoom.readStoredUiZoom?.(null), 130);
	assert.equal(uiZoom.readStoredUiZoom?.('{"uiZoom":145}'), 145);
	assert.equal(uiZoom.readStoredUiZoom?.('{"uiZoom":90}'), 130);
	assert.equal(uiZoom.readStoredUiZoom?.("not-json"), 130);
});
