export interface PromotionActionState {
	disabled: boolean;
	label: string;
	hint: string;
}

export function getPromotionActionState(
	selectedGrade: number | null,
	reason: string,
	selectedRankName: string | undefined,
	isSaving: boolean,
	isLoading: boolean,
): PromotionActionState {
	if (isLoading) {
		return {
			disabled: true,
			label: "Loading Ranks...",
			hint: "Loading the approved rank structure for this agency.",
		};
	}

	const label = selectedGrade === null
		? "Select a Rank"
		: `Set Rank to ${selectedRankName || selectedGrade}`;

	if (isSaving) {
		return {
			disabled: true,
			label: "Updating Rank...",
			hint: "The rank change is being recorded across the LEO system.",
		};
	}

	if (selectedGrade === null) {
		return {
			disabled: true,
			label,
			hint: "Select the officer's new rank.",
		};
	}

	if (reason.trim().length < 3) {
		return {
			disabled: true,
			label,
			hint: "Enter a written reason of at least 3 characters.",
		};
	}

	return {
		disabled: false,
		label,
		hint: "Ready to update this officer's rank.",
	};
}

const personnelActionMessages: Record<string, string> = {
	assignment_required:
		"Personnel assignment required. Another authorized command member or an administrator must grant it.",
	rank_insufficient: "Your current rank does not authorize this personnel action.",
	target_rank_denied:
		"You can only change the rank of officers below you, and the new rank must remain below yours.",
	self_action_denied: "You cannot change your own rank through the MDT.",
	agency_scope_denied: "You can only manage officers in your own agency.",
	reason_required: "Enter a written reason of at least 3 characters.",
	configuration_invalid: "That rank is not valid for this officer's agency.",
	identity_unavailable: "The officer's authoritative LEO personnel record could not be found.",
	employment_restricted: "This personnel action is unavailable while your employment is restricted.",
	employment_inactive: "This personnel action requires active employment status.",
	service_unavailable: "The rank update could not be completed. No changes were saved.",
	duplicate_action: "This personnel action was already processed.",
};

export function personnelActionMessage(message: string | undefined): string {
	if (!message) return "The personnel action could not be completed.";
	return personnelActionMessages[message] || message;
}
