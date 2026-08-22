<script lang="ts">
	import { onMount } from "svelte";
	import type { AuthService } from "../services/authService.svelte";
	import { createFleetService } from "../services/fleetService.svelte";
	import type { FleetAsset, FleetAssignmentType } from "../interfaces/IFleet";
	import { isFleetAttention } from "../utils/fleetStatus";
	import { fleetOperatorSummary } from "../utils/fleetPresentation";

	interface Props { authService: AuthService }
	let { authService }: Props = $props();

	const fleet = createFleetService();
	let query = $state("");
	let statusFilter = $state("active");
	let commissionOpen = $state(false);
	let commissionStep = $state(1);
	let actionAsset = $state<FleetAsset | null>(null);
	let action = $state("");
	let notice = $state<{ type: "success" | "error"; text: string } | null>(null);

	let form = $state({
		catalogKey: "",
		motorPool: "",
		fleetNumber: "",
		plate: "",
		assignmentType: "general_pool" as FleetAssignmentType,
		assignedPersonnelId: "",
		assignmentKey: "",
		presetKey: "standard",
		reason: "",
	});

	let actionForm = $state({
		assignmentType: "general_pool" as FleetAssignmentType,
		assignedPersonnelId: "",
		assignmentKey: "",
		fleetNumber: "",
		plate: "",
		reason: "",
	});

	onMount(() => fleet.load());

	let canCommission = $derived(authService.hasAnyPermission("fleet.commission"));
	let canAssign = $derived(authService.hasAnyPermission("fleet.assign"));
	let canManage = $derived(authService.hasAnyPermission("fleet.manage"));
	let canOverride = $derived(authService.hasAnyPermission("fleet.override"));

	let selectedCatalog = $derived(fleet.bootstrap.catalog.find((item) => item.key === form.catalogKey));
	let availablePools = $derived(fleet.bootstrap.motorPools.filter((pool) => !selectedCatalog || pool.type === selectedCatalog.motorPoolType));
	let filteredAssets = $derived.by(() => {
		const search = query.trim().toLowerCase();
		return fleet.bootstrap.assets.filter((asset) => {
			const statusMatches = statusFilter === "all"
				|| (statusFilter === "active" && asset.status !== "retired")
				|| asset.status === statusFilter;
			const searchMatches = !search || [asset.fleetNumber, asset.plate, asset.model, asset.vehicleClass, asset.assignmentKey]
				.some((value) => String(value || "").toLowerCase().includes(search));
			return statusMatches && searchMatches;
		});
	});

	function statusLabel(value: string): string {
		return value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
	}

	function assignmentLabel(asset: FleetAsset): string {
		if (asset.assignmentType === "officer") {
			const person = fleet.bootstrap.personnel.find((item) => item.id === asset.assignedPersonnelId);
			return person ? `${person.rankName || "Officer"} ${person.name}` : "Assigned officer";
		}
		if (asset.assignmentType === "unit") return statusLabel(asset.assignmentKey || "Unit");
		return statusLabel(asset.assignmentType);
	}

	function operatorSummary(asset: FleetAsset) {
		return fleetOperatorSummary(asset, fleet.bootstrap.personnel);
	}

	function nextIdentity(): { fleetNumber: string; plate: string } {
		const highest = fleet.bootstrap.assets.reduce((value, asset) => Math.max(value, Number(asset.fleetNumber) || 0), 1000);
		const fleetNumber = String(highest + 1).padStart(4, "0");
		const prefix = ({ brpd: "BR", ebrso: "ES", lsp: "SP" } as Record<string, string>)[fleet.bootstrap.agency] || "GV";
		return { fleetNumber, plate: `${prefix}${fleetNumber}`.slice(0, 8) };
	}

	function openCommission(): void {
		const identity = nextIdentity();
		const firstCatalog = fleet.bootstrap.catalog[0];
		form = {
			catalogKey: firstCatalog?.key || "",
			motorPool: fleet.bootstrap.motorPools.find((pool) => pool.type === (firstCatalog?.motorPoolType || "ground"))?.key || "",
			fleetNumber: identity.fleetNumber,
			plate: identity.plate,
			assignmentType: "general_pool",
			assignedPersonnelId: "",
			assignmentKey: "",
			presetKey: firstCatalog?.presetKeys[0] || "standard",
			reason: "",
		};
		commissionStep = 1;
		commissionOpen = true;
	}

	function catalogChanged(): void {
		const catalog = fleet.bootstrap.catalog.find((item) => item.key === form.catalogKey);
		form.motorPool = fleet.bootstrap.motorPools.find((pool) => pool.type === (catalog?.motorPoolType || "ground"))?.key || "";
		form.presetKey = catalog?.presetKeys[0] || "standard";
	}

	function validCommissionStep(): boolean {
		if (commissionStep === 1) return Boolean(form.catalogKey && form.motorPool && form.fleetNumber && form.plate);
		if (commissionStep === 2 && form.assignmentType === "officer") return Boolean(form.assignedPersonnelId);
		if (commissionStep === 2 && form.assignmentType === "unit") return form.assignmentKey.trim().length >= 2;
		return true;
	}

	async function commission(): Promise<void> {
		const result = await fleet.commission({
			catalogKey: form.catalogKey,
			motorPool: form.motorPool,
			fleetNumber: form.fleetNumber,
			plate: form.plate.toUpperCase().replaceAll(" ", ""),
			assignmentType: form.assignmentType,
			assignedPersonnelId: form.assignmentType === "officer" ? Number(form.assignedPersonnelId) : undefined,
			assignmentKey: form.assignmentType === "unit" ? form.assignmentKey : undefined,
			presetKey: form.presetKey,
			reason: form.reason,
		});
		if (!result.success) return showNotice("error", fleet.reasonLabel(result.reason));
		showNotice("success", `Fleet ${result.data?.fleetNumber || form.fleetNumber} commissioned`);
		commissionOpen = false;
		await fleet.load();
	}

	function openAction(asset: FleetAsset, selectedAction: string): void {
		actionAsset = asset;
		action = selectedAction;
		actionForm = {
			assignmentType: asset.assignmentType,
			assignedPersonnelId: asset.assignedPersonnelId ? String(asset.assignedPersonnelId) : "",
			assignmentKey: asset.assignmentKey || "",
			fleetNumber: asset.fleetNumber,
			plate: asset.plate,
			reason: "",
		};
	}

	async function executeAction(): Promise<void> {
		if (!actionAsset) return;
		let result;
		if (action === "assign") {
			result = await fleet.assign({
				assetId: actionAsset.id,
				assignmentType: actionForm.assignmentType,
				assignedPersonnelId: actionForm.assignmentType === "officer" ? Number(actionForm.assignedPersonnelId) : undefined,
				assignmentKey: actionForm.assignmentType === "unit" ? actionForm.assignmentKey : undefined,
				reason: actionForm.reason,
			});
		} else if (action === "renumber") {
			result = await fleet.renumber({
				assetId: actionAsset.id,
				fleetNumber: actionForm.fleetNumber,
				plate: actionForm.plate.toUpperCase().replaceAll(" ", ""),
				reason: actionForm.reason,
			});
		} else {
			result = await fleet.setStatus({ assetId: actionAsset.id, action, reason: actionForm.reason });
		}
		if (!result.success) return showNotice("error", fleet.reasonLabel(result.reason));
		showNotice("success", `Fleet ${actionAsset.fleetNumber} updated`);
		actionAsset = null;
		await fleet.load();
	}

	function showNotice(type: "success" | "error", text: string): void {
		notice = { type, text };
		setTimeout(() => { notice = null; }, 3500);
	}
</script>

<section class="fleet-page">
	<header class="page-header">
		<div>
			<p class="eyebrow">{fleet.bootstrap.agency.toUpperCase()} MOTOR POOL</p>
			<h1>Government Fleet</h1>
			<p class="subtitle">Permanent agency assets, assignments, availability, and recovery.</p>
		</div>
		{#if canCommission}
			<button class="primary" onclick={openCommission}><span class="material-icons">add</span>Commission Vehicle</button>
		{/if}
	</header>

	{#if notice}<div class:success={notice.type === "success"} class:error={notice.type === "error"} class="notice">{notice.text}</div>{/if}
	{#if fleet.error}<div class="notice error">{fleet.error}</div>{/if}

	<div class="toolbar">
		<label class="search"><span class="material-icons">search</span><input bind:value={query} placeholder="Fleet number, plate, model, or unit" /></label>
		<select bind:value={statusFilter} aria-label="Fleet status filter">
			<option value="active">Active assets</option><option value="available">Available</option>
			<option value="checked_out">Checked out</option><option value="reserved">Reserved</option>
			<option value="out_of_service">Out of service</option><option value="recovery_pending">Recovery pending</option>
			<option value="retired">Retired</option><option value="all">All assets</option>
		</select>
		<button class="secondary" onclick={() => fleet.load()} disabled={fleet.loading}><span class="material-icons">refresh</span>Refresh</button>
	</div>

	<div class="stats">
		<div><strong>{fleet.bootstrap.assets.length}</strong><span>Total assets</span></div>
		<div><strong>{fleet.bootstrap.assets.filter((asset) => asset.status === "available").length}</strong><span>Available</span></div>
		<div><strong>{fleet.bootstrap.assets.filter((asset) => asset.status === "checked_out").length}</strong><span>Checked out</span></div>
		<div><strong>{fleet.bootstrap.assets.filter(isFleetAttention).length}</strong><span>Attention</span></div>
	</div>

	{#if fleet.loading}
		<div class="empty"><span class="material-icons spin">sync</span>Loading fleet inventory</div>
	{:else if filteredAssets.length === 0}
		<div class="empty"><span class="material-icons">garage</span>No fleet assets match this view</div>
	{:else}
		<div class="asset-grid">
			{#each filteredAssets as asset (asset.id)}
				{@const usage = operatorSummary(asset)}
				<article class="asset-card">
					<div class="asset-top"><div><span class="fleet-number">FLEET {asset.fleetNumber}</span><h2>{asset.model}</h2></div><span class="status {asset.status}">{statusLabel(asset.status)}</span></div>
					<div class="plate">{asset.plate}</div>
					<dl>
						<div><dt>Class</dt><dd>{statusLabel(asset.vehicleClass)}</dd></div>
						<div><dt>Assignment</dt><dd>{assignmentLabel(asset)}</dd></div>
						<div><dt>Home motor pool</dt><dd>{fleet.bootstrap.motorPools.find((pool) => pool.key === asset.homeMotorPool)?.label || asset.homeMotorPool}</dd></div>
						<div><dt>Condition</dt><dd>{Math.round(asset.bodyHealth ?? 1000)}/1000, {Math.round(asset.fuel ?? 100)}% fuel</dd></div>
						<div><dt>Maintenance</dt><dd class:service-due={asset.serviceDue}>{asset.serviceDue ? `Service required, ${Math.round(asset.maintenance?.lowestHealth ?? 0)}% lowest part` : asset.maintenanceStatus === "operational" ? "Operational" : "No service data"}</dd></div>
						<div><dt>{usage.label}</dt><dd title={`${usage.operator}${usage.timestamp ? `, ${usage.timestamp}` : ""}`}>{usage.operator}{usage.timestamp ? `, ${usage.timestamp}` : ""}</dd></div>
					</dl>
					{#if asset.status !== "retired"}
						<div class="actions">
							{#if canAssign}<button onclick={() => openAction(asset, "assign")}>Assign</button>{/if}
							{#if canManage && asset.status === "available"}<button onclick={() => openAction(asset, "reserve")}>Reserve</button><button onclick={() => openAction(asset, "out_of_service")}>Out of service</button>{/if}
							{#if canManage && (asset.status === "reserved" || asset.status === "out_of_service")}<button onclick={() => openAction(asset, "release")}>Release</button>{/if}
							{#if canOverride && asset.status === "recovery_pending"}<button onclick={() => openAction(asset, "recover")}>Recover</button>{/if}
							{#if canOverride && asset.status !== "checked_out"}<button onclick={() => openAction(asset, "renumber")}>Renumber</button><button class="danger" onclick={() => openAction(asset, "retire")}>Retire</button>{/if}
						</div>
					{/if}
				</article>
			{/each}
		</div>
	{/if}
</section>

{#if commissionOpen}
	<div class="modal-backdrop" role="presentation">
		<div class="modal" role="dialog" aria-modal="true" aria-label="Commission fleet vehicle">
			<header><div><p class="eyebrow">COMMISSIONING, STEP {commissionStep} OF 3</p><h2>New Government Asset</h2></div><button class="icon" aria-label="Close" onclick={() => commissionOpen = false}>×</button></header>
			<div class="steps"><span class:active={commissionStep >= 1}>Vehicle</span><span class:active={commissionStep >= 2}>Assignment</span><span class:active={commissionStep >= 3}>Review</span></div>
			<div class="modal-body">
				{#if commissionStep === 1}
					<div class="field-grid">
						<label>Approved vehicle<select bind:value={form.catalogKey} onchange={catalogChanged}>{#each fleet.bootstrap.catalog as item}<option value={item.key}>{item.label}</option>{/each}</select></label>
						<label>Home motor pool<select bind:value={form.motorPool}>{#each availablePools as pool}<option value={pool.key}>{pool.label}</option>{/each}</select></label>
						<label>Fleet number<input maxlength="4" bind:value={form.fleetNumber} /></label>
						<label>Permanent plate<input maxlength="8" bind:value={form.plate} /></label>
						<label>Approved setup<select bind:value={form.presetKey}>{#each selectedCatalog?.presetKeys || [] as key}<option value={key}>{fleet.bootstrap.presets[key]?.label || key}</option>{/each}</select></label>
					</div>
				{:else if commissionStep === 2}
					<div class="field-grid">
						<label>Assignment type<select bind:value={form.assignmentType}><option value="general_pool">General agency pool</option><option value="officer">Officer</option><option value="training_pool">Field training pool</option><option value="command_pool">Command pool</option><option value="unit">Specialized unit</option></select></label>
						{#if form.assignmentType === "officer"}<label>Assigned officer<select bind:value={form.assignedPersonnelId}><option value="">Select officer</option>{#each fleet.bootstrap.personnel as person}<option value={person.id}>{person.rankName} {person.name}, {person.badge || person.callsign}</option>{/each}</select></label>{/if}
						{#if form.assignmentType === "unit"}<label>Unit assignment<input maxlength="64" bind:value={form.assignmentKey} placeholder="traffic, tactical_unit, aviation_unit" /></label>{/if}
					</div>
				{:else}
					<div class="review"><div><span>Vehicle</span><strong>{selectedCatalog?.label}</strong></div><div><span>Fleet identity</span><strong>{form.fleetNumber}, {form.plate}</strong></div><div><span>Motor pool</span><strong>{fleet.bootstrap.motorPools.find((pool) => pool.key === form.motorPool)?.label}</strong></div><div><span>Assignment</span><strong>{statusLabel(form.assignmentType)}</strong></div></div>
					<label>Commissioning reason<textarea maxlength="255" bind:value={form.reason} placeholder="State why this asset is being commissioned"></textarea></label>
				{/if}
			</div>
			<footer><button class="secondary" onclick={() => commissionStep === 1 ? (commissionOpen = false) : commissionStep--}>{commissionStep === 1 ? "Cancel" : "Back"}</button>{#if commissionStep < 3}<button class="primary" disabled={!validCommissionStep()} onclick={() => commissionStep++}>Continue</button>{:else}<button class="primary" disabled={fleet.saving || form.reason.trim().length < 3} onclick={commission}>{fleet.saving ? "Commissioning" : "Commission Asset"}</button>{/if}</footer>
		</div>
	</div>
{/if}

{#if actionAsset}
	<div class="modal-backdrop" role="presentation">
		<div class="modal small" role="dialog" aria-modal="true" aria-label="Fleet management action">
			<header><div><p class="eyebrow">FLEET {actionAsset.fleetNumber}</p><h2>{statusLabel(action)}</h2></div><button class="icon" aria-label="Close" onclick={() => actionAsset = null}>×</button></header>
			<div class="modal-body">
				{#if action === "assign"}
					<label>Assignment type<select bind:value={actionForm.assignmentType}><option value="general_pool">General agency pool</option><option value="officer">Officer</option><option value="training_pool">Field training pool</option><option value="command_pool">Command pool</option><option value="unit">Specialized unit</option></select></label>
					{#if actionForm.assignmentType === "officer"}<label>Assigned officer<select bind:value={actionForm.assignedPersonnelId}><option value="">Select officer</option>{#each fleet.bootstrap.personnel as person}<option value={person.id}>{person.rankName} {person.name}</option>{/each}</select></label>{/if}
					{#if actionForm.assignmentType === "unit"}<label>Unit assignment<input maxlength="64" bind:value={actionForm.assignmentKey} /></label>{/if}
				{:else if action === "renumber"}
					<div class="field-grid"><label>Fleet number<input maxlength="4" bind:value={actionForm.fleetNumber} /></label><label>Permanent plate<input maxlength="8" bind:value={actionForm.plate} /></label></div>
				{/if}
				<label>Required reason<textarea maxlength="255" bind:value={actionForm.reason} placeholder="Document the reason for this fleet action"></textarea></label>
			</div>
			<footer><button class="secondary" onclick={() => actionAsset = null}>Cancel</button><button class:danger={action === "retire"} class="primary" disabled={fleet.saving || actionForm.reason.trim().length < 3} onclick={executeAction}>Confirm</button></footer>
		</div>
	</div>
{/if}

<style>
	.fleet-page { padding: 22px; min-height: 100%; background: var(--card-dark-bg); color: rgba(255,255,255,.88); }
	.page-header, .toolbar, .asset-top, .actions, .modal header, .modal footer, .steps { display: flex; align-items: center; }
	.page-header { justify-content: space-between; gap: 18px; margin-bottom: 18px; }
	h1, h2, p { margin: 0; } h1 { font-size: 24px; } h2 { font-size: 16px; text-transform: capitalize; }
	.eyebrow { color: rgba(var(--accent-text-rgb), .72); font-size: 9px; font-weight: 800; letter-spacing: 1.2px; }
	.subtitle { color: rgba(255,255,255,.42); font-size: 11px; margin-top: 5px; }
	button, input, select, textarea { font: inherit; } button { cursor: pointer; }
	.primary, .secondary, .actions button { border-radius: 7px; padding: 9px 13px; border: 1px solid rgba(255,255,255,.09); color: rgba(255,255,255,.82); background: rgba(255,255,255,.045); display: inline-flex; gap: 6px; align-items: center; }
	.primary { background: rgba(var(--accent-rgb), .25); border-color: rgba(var(--accent-rgb), .42); } .primary .material-icons, .secondary .material-icons { font-size: 16px; }
	button:disabled { opacity: .4; cursor: not-allowed; } .danger { color: #fca5a5 !important; border-color: rgba(239,68,68,.25) !important; }
	.toolbar { gap: 10px; padding: 10px; background: rgba(255,255,255,.025); border: 1px solid rgba(255,255,255,.06); border-radius: 9px; }
	.search { flex: 1; display: flex; align-items: center; gap: 7px; } .search .material-icons { font-size: 17px; color: rgba(255,255,255,.3); }
	input, select, textarea { width: 100%; box-sizing: border-box; border: 1px solid rgba(255,255,255,.09); border-radius: 6px; padding: 9px 10px; color: rgba(255,255,255,.84); background: #15171a; outline: none; }
	.toolbar input { border: 0; background: transparent; padding: 5px; } .toolbar select { width: 170px; }
	.stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 9px; margin: 12px 0; } .stats div { padding: 12px; background: rgba(255,255,255,.025); border: 1px solid rgba(255,255,255,.055); border-radius: 8px; display: flex; flex-direction: column; } .stats strong { font-size: 20px; } .stats span { color: rgba(255,255,255,.35); font-size: 9px; text-transform: uppercase; letter-spacing: .7px; }
	.asset-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(310px, 1fr)); gap: 10px; }
	.asset-card { background: rgba(255,255,255,.025); border: 1px solid rgba(255,255,255,.06); border-radius: 10px; padding: 14px; }
	.asset-top { justify-content: space-between; gap: 10px; } .fleet-number { font-size: 9px; color: rgba(var(--accent-text-rgb),.7); font-weight: 800; letter-spacing: .8px; }
	.status { font-size: 8px; text-transform: uppercase; padding: 4px 7px; border-radius: 20px; background: rgba(255,255,255,.07); } .status.available { color: #86efac; background: rgba(34,197,94,.1); } .status.checked_out { color: #93c5fd; background: rgba(59,130,246,.1); } .status.recovery_pending, .status.out_of_service { color: #fca5a5; background: rgba(239,68,68,.1); }
	.plate { display: inline-block; margin: 10px 0; padding: 4px 9px; border-radius: 4px; background: #e8e4d6; color: #171717; font-weight: 900; font-size: 11px; letter-spacing: 1px; }
	dl { margin: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 8px; } dl div { min-width: 0; } dt { color: rgba(255,255,255,.3); font-size: 8px; text-transform: uppercase; } dd { margin: 2px 0 0; font-size: 10px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	dd.service-due { color: #fca5a5; }
	.actions { flex-wrap: wrap; gap: 5px; margin-top: 12px; padding-top: 10px; border-top: 1px solid rgba(255,255,255,.055); } .actions button { font-size: 9px; padding: 6px 8px; }
	.empty { display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 55px; color: rgba(255,255,255,.35); } .empty .material-icons { font-size: 34px; }
	.notice { padding: 9px 12px; border-radius: 7px; margin-bottom: 10px; font-size: 11px; } .notice.success { background: rgba(34,197,94,.1); color: #86efac; } .notice.error { background: rgba(239,68,68,.1); color: #fca5a5; }
	.modal-backdrop { position: fixed; inset: 0; z-index: 100; display: grid; place-items: center; background: rgba(0,0,0,.72); }
	.modal { width: min(680px, 85vw); max-height: 88vh; overflow: auto; background: #111316; border: 1px solid rgba(255,255,255,.1); border-radius: 12px; box-shadow: 0 24px 80px rgba(0,0,0,.45); } .modal.small { width: min(480px, 80vw); }
	.modal header, .modal footer { justify-content: space-between; padding: 15px 18px; border-bottom: 1px solid rgba(255,255,255,.07); } .modal footer { border: 0; border-top: 1px solid rgba(255,255,255,.07); justify-content: flex-end; gap: 8px; }
	.icon { border: 0; background: transparent; color: rgba(255,255,255,.5); font-size: 22px; }
	.steps { padding: 9px 18px; gap: 8px; } .steps span { flex: 1; text-align: center; padding: 6px; border-bottom: 2px solid rgba(255,255,255,.08); color: rgba(255,255,255,.3); font-size: 9px; text-transform: uppercase; } .steps span.active { color: rgba(var(--accent-text-rgb),.9); border-color: rgba(var(--accent-rgb),.7); }
	.modal-body { padding: 18px; display: flex; flex-direction: column; gap: 12px; } .field-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; } label { display: flex; flex-direction: column; gap: 5px; color: rgba(255,255,255,.45); font-size: 9px; font-weight: 700; text-transform: uppercase; letter-spacing: .4px; } textarea { min-height: 78px; resize: vertical; }
	.review { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; } .review div { padding: 10px; background: rgba(255,255,255,.03); border-radius: 7px; display: flex; flex-direction: column; } .review span { color: rgba(255,255,255,.3); font-size: 8px; text-transform: uppercase; } .review strong { font-size: 11px; margin-top: 3px; }
	.spin { animation: spin 1s linear infinite; } @keyframes spin { to { transform: rotate(360deg); } }
</style>
