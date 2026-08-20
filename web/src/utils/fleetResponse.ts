import type { FleetMutationResponse } from "../interfaces/IFleet";

const FAILURE_LABELS: Record<string, string> = {
	off_duty: "You must be on duty",
	agency_scope_denied: "That vehicle belongs to another agency",
	assignment_required: "The required unit assignment is missing",
	certification_required: "The required certification is missing or expired",
	duplicate_request: "That request was already processed",
	commission_failed: "The fleet number or plate is already registered",
	asset_checked_out: "Return or recover the vehicle before changing it",
	status_transition_denied: "That status change is not allowed",
	service_unavailable: "Fleet services are currently unavailable",
	service_error: "Fleet service failed while processing the request. Check the server console.",
	invalid_response: "Fleet service returned an invalid response. Check F8 for the diagnostic.",
	missing_failure_reason: "Fleet request was denied without a reason. Check F8 for the diagnostic.",
	missing_bootstrap_data: "Fleet service did not return its catalog data. Check F8 for the diagnostic.",
};

export function normalizeFleetResponse<T>(
	value: unknown,
	requireData = false,
): FleetMutationResponse<T> {
	if (!value || typeof value !== "object" || Array.isArray(value)) {
		return { success: false, reason: "invalid_response" };
	}

	const response = value as Record<string, unknown>;
	if (typeof response.success !== "boolean") {
		return { success: false, reason: "invalid_response" };
	}
	if (!response.success && (typeof response.reason !== "string" || !response.reason.trim())) {
		return { success: false, reason: "missing_failure_reason" };
	}
	if (response.success && requireData && (!response.data || typeof response.data !== "object" || Array.isArray(response.data))) {
		return { success: false, reason: "missing_bootstrap_data" };
	}

	return value as FleetMutationResponse<T>;
}

export function fleetFailureLabel(reason?: string): string {
	return FAILURE_LABELS[reason || ""] ?? (reason || "Fleet action failed").replaceAll("_", " ");
}
