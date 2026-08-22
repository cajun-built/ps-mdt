export const DEFAULT_UI_ZOOM = 130;
export const MIN_UI_ZOOM = 100;
export const MAX_UI_ZOOM = 200;
export const UI_ZOOM_EVENT = "ps-mdt:ui-zoom";
export const UI_PREFERENCES_STORAGE_KEY = "ps-mdt-preferences";

export interface UiZoomLayout {
	zoom: string;
	width: string;
	height: string;
}

export function normalizeUiZoom(value: unknown): number {
	const zoom = Number(value);
	if (!Number.isFinite(zoom) || zoom < MIN_UI_ZOOM || zoom > MAX_UI_ZOOM) {
		return DEFAULT_UI_ZOOM;
	}
	return zoom;
}

export function readStoredUiZoom(savedPreferences: string | null): number {
	if (!savedPreferences) return DEFAULT_UI_ZOOM;
	try {
		return normalizeUiZoom(JSON.parse(savedPreferences)?.uiZoom);
	} catch {
		return DEFAULT_UI_ZOOM;
	}
}

export function getUiZoomLayout(value: unknown): UiZoomLayout {
	const zoom = normalizeUiZoom(value);
	return {
		zoom: `${zoom}%`,
		width: "100%",
		height: "100%",
	};
}
