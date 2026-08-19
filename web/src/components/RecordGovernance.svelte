<script lang="ts">
	import { fetchNui } from "../utils/fetchNui";
	import { formatDateTime } from "../utils/datetime";
	import { globalNotifications } from "../services/notificationService.svelte";
	import { NUI_EVENTS } from "../constants/nuiEvents";

	type RecordType = "case" | "report" | "bolo" | "evidence";

	interface Supplement {
		id: number;
		author_citizenid: string;
		author_name: string;
		author_agency: string;
		content: string;
		created_at: string | number;
	}

	interface Revision {
		id: number;
		revision_number: number;
		action: string;
		author_citizenid: string;
		author_name: string;
		author_agency: string;
		reason: string;
		before_json?: string;
		after_json?: string;
		created_at: string | number;
	}

	interface GovernanceCapabilities {
		success: boolean;
		error?: string;
		canSupplement: boolean;
		canManageLifecycle: boolean;
		allowedTransitions: string[];
		lifecycleStatus?: string;
		owningAgency?: string | null;
		taskForceId?: string | null;
	}

	interface Props {
		recordType: RecordType;
		recordId: number;
		owningAgency?: string | null;
		taskForceId?: string | null;
		lifecycleStatus?: string | null;
		onChanged?: () => void | Promise<void>;
	}

	let {
		recordType,
		recordId,
		owningAgency = null,
		taskForceId = null,
		lifecycleStatus = "active",
		onChanged,
	}: Props = $props();

	let supplements = $state<Supplement[]>([]);
	let revisions = $state<Revision[]>([]);
	let supplementContent = $state("");
	let lifecycleReason = $state("");
	let selectedLifecycle = $state(lifecycleStatus || "active");
	let loading = $state(false);
	let submitting = $state(false);
	let loadedKey = $state("");
	let canSupplement = $state(false);
	let canManageLifecycle = $state(false);
	let allowedTransitions = $state<string[]>([]);
	let authoritativeAgency = $state<string | null>(owningAgency);
	let authoritativeTaskForce = $state<string | null>(taskForceId);
	let currentLifecycle = $state(lifecycleStatus || "active");

	$effect(() => {
		const key = `${recordType}:${recordId}`;
		if (recordId > 0 && key !== loadedKey) {
			loadedKey = key;
			currentLifecycle = lifecycleStatus || "active";
			selectedLifecycle = "";
			canSupplement = false;
			canManageLifecycle = false;
			allowedTransitions = [];
			void loadGovernance();
		}
	});

	$effect(() => {
		if (lifecycleStatus) currentLifecycle = lifecycleStatus;
	});

	async function loadGovernance() {
		loading = true;
		try {
			const [supplementResponse, revisionResponse, capabilityResponse] = await Promise.all([
				fetchNui<{ success: boolean; error?: string; supplements: Supplement[] }>(
					"getRecordSupplements",
					{ recordType, recordId },
					{ success: true, supplements: [] },
				),
				fetchNui<{ success: boolean; error?: string; revisions: Revision[] }>(
					"getRecordRevisions",
					{ recordType, recordId },
					{ success: true, revisions: [] },
				),
				fetchNui<GovernanceCapabilities>(
					NUI_EVENTS.RECORD_GOVERNANCE.GET_CAPABILITIES,
					{ recordType, recordId },
					{
						success: true,
						canSupplement: false,
						canManageLifecycle: false,
						allowedTransitions: [],
					},
				),
			]);
			supplements = supplementResponse.supplements || [];
			revisions = revisionResponse.revisions || [];
			canSupplement = capabilityResponse.success && capabilityResponse.canSupplement === true;
			canManageLifecycle = capabilityResponse.success && capabilityResponse.canManageLifecycle === true;
			allowedTransitions = capabilityResponse.allowedTransitions || [];
			currentLifecycle = capabilityResponse.lifecycleStatus || lifecycleStatus || "active";
			selectedLifecycle = allowedTransitions[0] || "";
			authoritativeAgency = capabilityResponse.owningAgency || owningAgency;
			authoritativeTaskForce = capabilityResponse.taskForceId || taskForceId;
		} catch {
			globalNotifications.error("Unable to load record history");
		} finally {
			loading = false;
		}
	}

	async function addSupplement() {
		const content = supplementContent.trim();
		if (!canSupplement || !content || submitting) return;
		submitting = true;
		try {
			const response = await fetchNui<{ success: boolean; error?: string }>(
				"addRecordSupplement",
				{ recordType, recordId, content },
				{ success: true },
			);
			if (!response.success) {
				globalNotifications.error(response.error || "Unable to add supplement");
				return;
			}
			supplementContent = "";
			await loadGovernance();
			globalNotifications.success("Supplement added to the permanent record");
		} catch {
			globalNotifications.error("Unable to add supplement");
		} finally {
			submitting = false;
		}
	}

	async function updateLifecycle() {
		const reason = lifecycleReason.trim();
		if (!canManageLifecycle || !selectedLifecycle || !reason || submitting) {
			globalNotifications.error("A written lifecycle reason is required");
			return;
		}
		submitting = true;
		try {
			const response = await fetchNui<{ success: boolean; error?: string }>(
				"setRecordLifecycle",
				{ recordType, recordId, status: selectedLifecycle, reason },
				{ success: true },
			);
			if (!response.success) {
				globalNotifications.error(response.error || "Unable to update record lifecycle");
				return;
			}
			lifecycleReason = "";
			await loadGovernance();
			await onChanged?.();
			globalNotifications.success("Record lifecycle updated");
		} catch {
			globalNotifications.error("Unable to update record lifecycle");
		} finally {
			submitting = false;
		}
	}

	function displayValue(value?: string | null) {
		return value && value.trim() ? value : "None";
	}

	function displayStatus(value: string) {
		return value.replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
	}
</script>

<section class="governance-card">
	<header class="governance-header">
		<div>
			<h3>Record governance</h3>
			<p>Agency ownership, permanent supplements, lifecycle controls, and revision history.</p>
		</div>
		<span class="status-badge">{displayStatus(currentLifecycle)}</span>
	</header>

	<div class="ownership-grid">
		<div><span>Agency ownership</span><strong>{displayValue(authoritativeAgency)?.toUpperCase()}</strong></div>
		<div><span>Task force</span><strong>{displayValue(authoritativeTaskForce)}</strong></div>
		<div><span>Record</span><strong>{recordType.toUpperCase()} #{recordId}</strong></div>
	</div>

	<div class="governance-grid">
		<div class="governance-panel">
			<h4>Supplemental narrative</h4>
			<p class="panel-help">Add new facts without altering or deleting the original submission.</p>
			{#if canSupplement}
				<textarea bind:value={supplementContent} maxlength="16000" rows="4" placeholder="Enter the supplemental narrative"></textarea>
				<button type="button" onclick={addSupplement} disabled={!supplementContent.trim() || submitting}>
					Add permanent supplement
				</button>
			{:else}
				<p class="access-note">Your current assignment does not authorize supplements to this record.</p>
			{/if}
			{#if loading}
				<p class="empty">Loading supplements...</p>
			{:else if supplements.length === 0}
				<p class="empty">No supplements filed.</p>
			{:else}
				<div class="history-list">
					{#each supplements as supplement (supplement.id)}
						<article class="history-entry">
							<div class="entry-meta">
								<strong>{supplement.author_name}</strong>
								<span>{supplement.author_agency?.toUpperCase()}, {formatDateTime(supplement.created_at)}</span>
							</div>
							<p>{supplement.content}</p>
						</article>
					{/each}
				</div>
			{/if}
		</div>

		<div class="governance-panel">
			<h4>Lifecycle control</h4>
			<p class="panel-help">Status changes are permanent, permission checked, and require a written reason.</p>
			{#if canManageLifecycle && allowedTransitions.length > 0}
				<select bind:value={selectedLifecycle}>
					{#each allowedTransitions as status}
						<option value={status}>{displayStatus(status)}</option>
					{/each}
				</select>
				<textarea bind:value={lifecycleReason} maxlength="500" rows="3" placeholder="Written reason for this lifecycle change"></textarea>
				<button type="button" onclick={updateLifecycle} disabled={!selectedLifecycle || !lifecycleReason.trim() || submitting}>
					Apply lifecycle change
				</button>
			{:else if canManageLifecycle}
				<p class="access-note">This record is in a terminal lifecycle state.</p>
			{:else}
				<p class="access-note">Lifecycle changes require an authorized supervisor from the owning agency.</p>
			{/if}

			<h4 class="revision-title">Revision history</h4>
			{#if loading}
				<p class="empty">Loading revisions...</p>
			{:else if revisions.length === 0}
				<p class="empty">No revisions recorded.</p>
			{:else}
				<div class="history-list">
					{#each revisions as revision (revision.id)}
						<details class="revision-entry">
							<summary>
								<span>Revision {revision.revision_number}, {displayStatus(revision.action)}</span>
								<small>{formatDateTime(revision.created_at)}</small>
							</summary>
							<p><strong>{revision.author_name}</strong>, {revision.author_agency?.toUpperCase()}</p>
							<p>{revision.reason}</p>
						</details>
					{/each}
				</div>
			{/if}
		</div>
	</div>
</section>

<style>
	.governance-card { border: 1px solid rgba(148, 163, 184, .18); border-radius: 8px; background: rgba(11, 16, 24, .72); padding: 16px; color: #dce4ee; }
	.governance-header { display: flex; justify-content: space-between; gap: 16px; align-items: flex-start; margin-bottom: 14px; }
	h3, h4, p { margin: 0; }
	h3 { font-size: 15px; letter-spacing: .02em; }
	h4 { font-size: 12px; text-transform: uppercase; letter-spacing: .08em; color: #d7e1ec; }
	.governance-header p, .panel-help { margin-top: 4px; color: #8190a1; font-size: 11px; line-height: 1.45; }
	.status-badge { border: 1px solid rgba(59, 130, 246, .35); background: rgba(59, 130, 246, .12); color: #9fc5ff; border-radius: 999px; padding: 5px 9px; font-size: 10px; white-space: nowrap; }
	.ownership-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; margin-bottom: 12px; }
	.ownership-grid div { border: 1px solid rgba(148, 163, 184, .12); background: rgba(255, 255, 255, .02); border-radius: 6px; padding: 9px; display: flex; flex-direction: column; gap: 3px; }
	.ownership-grid span { color: #718095; font-size: 9px; text-transform: uppercase; letter-spacing: .09em; }
	.ownership-grid strong { font-size: 11px; color: #d7e1ec; overflow-wrap: anywhere; }
	.governance-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
	.governance-panel { border: 1px solid rgba(148, 163, 184, .12); border-radius: 6px; padding: 12px; min-width: 0; }
	textarea, select { width: 100%; box-sizing: border-box; border: 1px solid rgba(148, 163, 184, .18); border-radius: 5px; background: #0b1119; color: #dce4ee; font: inherit; font-size: 11px; padding: 9px; margin-top: 9px; resize: vertical; }
	button { margin-top: 8px; border: 1px solid rgba(59, 130, 246, .35); border-radius: 5px; background: rgba(37, 99, 235, .18); color: #b9d4ff; padding: 8px 11px; font-size: 10px; font-weight: 650; cursor: pointer; }
	button:hover:not(:disabled) { background: rgba(37, 99, 235, .28); }
	button:disabled { opacity: .45; cursor: not-allowed; }
	.history-list { display: flex; flex-direction: column; gap: 7px; max-height: 230px; overflow-y: auto; margin-top: 10px; }
	.history-entry, .revision-entry { border: 1px solid rgba(148, 163, 184, .1); border-radius: 5px; background: rgba(255, 255, 255, .018); padding: 9px; }
	.entry-meta { display: flex; justify-content: space-between; gap: 8px; font-size: 10px; }
	.entry-meta span, .revision-entry small { color: #718095; font-size: 9px; }
	.history-entry p, .revision-entry p { margin-top: 7px; color: #aeb9c8; font-size: 10px; line-height: 1.5; white-space: pre-wrap; }
	.revision-entry summary { cursor: pointer; display: flex; justify-content: space-between; gap: 8px; color: #c8d3df; font-size: 10px; }
	.revision-title { margin-top: 18px; }
	.empty { color: #647286; font-size: 10px; margin-top: 10px; }
	.access-note { margin-top: 10px; border: 1px solid rgba(148, 163, 184, .12); border-radius: 5px; background: rgba(255, 255, 255, .018); color: #8190a1; font-size: 10px; line-height: 1.5; padding: 9px; }
	@media (max-width: 900px) {
		.governance-grid { grid-template-columns: 1fr; }
		.ownership-grid { grid-template-columns: 1fr; }
	}
</style>
