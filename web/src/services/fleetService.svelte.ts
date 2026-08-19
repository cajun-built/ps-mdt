import { NUI_EVENTS } from "../constants/nuiEvents";
import type {
	FleetAsset,
	FleetBootstrap,
	FleetCommissionPayload,
	FleetMutationResponse,
} from "../interfaces/IFleet";
import { fetchNui } from "../utils/fetchNui";
import { isEnvBrowser } from "../utils/misc";

const EMPTY_BOOTSTRAP: FleetBootstrap = {
	agency: "brpd",
	permissions: {},
	catalog: [],
	motorPools: [],
	personnel: [],
	assets: [],
	presets: {},
};

function mockBootstrap(): FleetBootstrap {
	return {
		...EMPTY_BOOTSTRAP,
		permissions: {
			"fleet.view": true,
			"fleet.manage": true,
			"fleet.commission": true,
			"fleet.assign": true,
			"fleet.override": true,
		},
		catalog: [{
			key: "brpd_patrol",
			model: "police",
			label: "BRPD Patrol Sedan",
			vehicleClass: "patrol",
			livery: 0,
			presetKeys: ["standard"],
			motorPoolType: "ground",
		}],
		motorPools: [{ key: "brpd_hq", label: "BRPD Headquarters Motor Pool", type: "ground" }],
		presets: { standard: { label: "Standard Patrol Setup" } },
	};
}

export function createFleetService() {
	let bootstrap = $state<FleetBootstrap>(EMPTY_BOOTSTRAP);
	let loading = $state(false);
	let saving = $state(false);
	let error = $state<string | null>(null);

	function actionId(operation: string): string {
		const unique = globalThis.crypto?.randomUUID?.() ?? `${Date.now()}:${Math.random().toString(16).slice(2)}`;
		return `fleet:${operation}:${unique}`.slice(0, 64);
	}

	function reasonLabel(reason?: string): string {
		const labels: Record<string, string> = {
			off_duty: "You must be on duty",
			agency_scope_denied: "That vehicle belongs to another agency",
			assignment_required: "The required unit assignment is missing",
			certification_required: "The required certification is missing or expired",
			duplicate_request: "That request was already processed",
			commission_failed: "The fleet number or plate is already registered",
			asset_checked_out: "Return or recover the vehicle before changing it",
			status_transition_denied: "That status change is not allowed",
			service_unavailable: "Fleet services are currently unavailable",
		};
		return labels[reason || ""] ?? (reason || "Fleet action failed").replaceAll("_", " ");
	}

	async function load(): Promise<boolean> {
		loading = true;
		error = null;
		try {
			if (isEnvBrowser()) {
				bootstrap = mockBootstrap();
				return true;
			}
			const result = await fetchNui<FleetMutationResponse<FleetBootstrap>>(
				NUI_EVENTS.FLEET.GET_BOOTSTRAP,
				{},
				{ success: false, reason: "service_unavailable" },
			);
			if (!result.success || !result.data) {
				error = reasonLabel(result.reason);
				return false;
			}
			bootstrap = result.data;
			return true;
		} catch {
			error = "Fleet services are currently unavailable";
			return false;
		} finally {
			loading = false;
		}
	}

	async function mutate<T>(event: string, payload: Record<string, unknown>): Promise<FleetMutationResponse<T>> {
		saving = true;
		error = null;
		try {
			const result = await fetchNui<FleetMutationResponse<T>>(event as never, payload, {
				success: isEnvBrowser(),
			});
			if (!result.success) error = reasonLabel(result.reason);
			return result;
		} catch {
			error = "Fleet services are currently unavailable";
			return { success: false, reason: "service_unavailable" };
		} finally {
			saving = false;
		}
	}

	async function commission(payload: Omit<FleetCommissionPayload, "actionId">) {
		return mutate<FleetAsset>(NUI_EVENTS.FLEET.COMMISSION, {
			...payload,
			actionId: actionId("commission"),
		});
	}

	async function assign(payload: Record<string, unknown>) {
		return mutate<FleetAsset>(NUI_EVENTS.FLEET.ASSIGN, {
			...payload,
			actionId: actionId("assign"),
		});
	}

	async function setStatus(payload: Record<string, unknown>) {
		return mutate<FleetAsset>(NUI_EVENTS.FLEET.SET_STATUS, {
			...payload,
			actionId: actionId(String(payload.action || "status")),
		});
	}

	async function renumber(payload: Record<string, unknown>) {
		return mutate<FleetAsset>(NUI_EVENTS.FLEET.RENUMBER, {
			...payload,
			actionId: actionId("renumber"),
		});
	}

	return {
		load,
		commission,
		assign,
		setStatus,
		renumber,
		reasonLabel,
		get bootstrap() { return bootstrap; },
		get loading() { return loading; },
		get saving() { return saving; },
		get error() { return error; },
	};
}

export type FleetService = ReturnType<typeof createFleetService>;
