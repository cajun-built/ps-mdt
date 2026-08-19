<script lang="ts">
	import { onMount, onDestroy } from "svelte";
	import { formatDate, formatTime } from "../utils/datetime";
	import { fetchNui } from "../utils/fetchNui";
	import { NUI_EVENTS } from "../constants/nuiEvents";
	import type { createTabService } from "../services/tabService.svelte";
	import { createDashboardService } from "../services/dashboardService.svelte";
	import { openReportInEditor } from "../stores/reportsStore";
	import { mdtStore } from "../stores/mdtStore";
	import ReportItem from "../components/dashboard/ReportItem.svelte";
	import DispatchStatusWidget from "../components/dashboard/DispatchStatusWidget.svelte";
	import type { PlayerData } from "../interfaces/IPlayerData";

	let {
		signOut,
		playerData,
		tabService,
	}: {
		signOut: () => void;
		playerData: PlayerData | null;
		tabService: ReturnType<typeof createTabService>;
	} = $props();

	const dashboard = createDashboardService();
	const EMPTY_CALLSIGN_VALUES = new Set(["", "NIL", "NO CALLSIGN", "NONE", "NULL"]);

	let currentTime = $state(formatTime(new Date()));
	let currentDate = $state(formatDate(new Date()));
	let reportOpened: number | null = $state(null);
	let callsignLoading = $state(true);
	let localCallsign = $state("");
	let clockTimer: ReturnType<typeof setInterval> | null = null;

	let warrants = $derived(dashboard.activeWarrants ?? []);
	let bolos = $derived(dashboard.activeBolos ?? []);
	let reports = $derived(dashboard.recentReports ?? []);
	let bulletin = $derived(
		dashboard.bulletins?.[dashboard.currentBulletinIndex]?.content ?? dashboard.bulletinContent ?? "No active bulletins",
	);
	let impound = $derived(
		dashboard.usageMetrics?.impound ?? { held: 0, outstanding: 0, oldestDays: 0, impoundedLast7: 0 },
	);

	function isValidCallsign(value: unknown): boolean {
		if (value == null) return false;
		const normalized = String(value).trim().toUpperCase();
		return !EMPTY_CALLSIGN_VALUES.has(normalized) && normalized.length >= 2;
	}

	let hasCallsign = $derived(isValidCallsign(localCallsign));

	async function fetchCallsign() {
		callsignLoading = true;
		const result = await fetchNui<{ callsign?: string }>(
			NUI_EVENTS.DASHBOARD.GET_CALLSIGN,
			{},
			{ callsign: playerData?.metadata?.callsign ?? "" },
		);
		const callsign = String(result?.callsign ?? playerData?.metadata?.callsign ?? "").trim();
		if (isValidCallsign(callsign)) localCallsign = callsign;
		callsignLoading = false;
	}

	function navigate(tab: "Reports" | "BOLOs" | "Warrants" | "Roster" | "Calendar" | "Cases") {
		tabService.setActiveTab(tab);
		const activeInstance = tabService.getActiveInstance();
		if (activeInstance) tabService.setInstanceTab(activeInstance.id, tab);
	}

	function openWarrant(reportId: number) {
		if (!reportId) return;
		openReportInEditor(String(reportId));
		navigate("Reports");
	}

	function openReport(id: number) {
		reportOpened = reportOpened === id ? null : id;
	}

	function viewReport(id: number) {
		openReportInEditor(String(id));
		navigate("Reports");
	}

	function toggleDuty() {
		fetchNui(NUI_EVENTS.NAVIGATION.TOGGLE_DUTY);
	}

	function handleSignOut() {
		mdtStore.reset();
		signOut();
	}

	onMount(async () => {
		dashboard.initialize();
		dashboard.startCarouselTimer();
		await fetchCallsign();
		clockTimer = setInterval(() => {
			const now = new Date();
			currentTime = formatTime(now);
			currentDate = formatDate(now);
		}, 1000);
	});

	onDestroy(() => {
		dashboard.destroy();
		if (clockTimer) clearInterval(clockTimer);
	});
</script>

<div class="command-dashboard">
	<header class="dashboard-header">
		<div class="page-heading">
			<h1>Dashboard</h1>
			<div class="heading-meta">
				<span>{currentDate}</span>
				<span class="shift-pill">Active shift</span>
			</div>
		</div>

		<div class="bulletin-line" title={bulletin}>
			<span class="material-icons">campaign</span>
			<div class="bulletin-copy">
				<span class="eyebrow">Department bulletin</span>
				<span class="bulletin-message">{bulletin}</span>
			</div>
		</div>

		<div class="header-actions">
			{#if !callsignLoading}
				<div class="callsign-control" title="Assigned callsign">
					<span class="material-icons">badge</span>
					<span><small>Callsign</small>{hasCallsign ? localCallsign : "Not set"}</span>
				</div>
			{/if}
			<button class="shift-button" onclick={toggleDuty} title="End duty shift">
				<span class="material-icons">power_settings_new</span>
				<span>End shift</span>
			</button>
			<button class="signout-button" onclick={handleSignOut} title="Close terminal">
				<span class="material-icons">logout</span>
			</button>
		</div>
	</header>

	<section class="kpi-strip" aria-label="Shift summary">
		<button class="kpi" onclick={() => navigate("Warrants")}>
			<span class="kpi-icon danger material-icons">gavel</span>
			<span class="kpi-copy"><small>Active warrants</small><strong class="danger-text">{warrants.length}</strong><em>Require attention</em></span>
		</button>
		<button class="kpi" onclick={() => navigate("BOLOs")}>
			<span class="kpi-icon warning material-icons">my_location</span>
			<span class="kpi-copy"><small>Active BOLOs</small><strong class="warning-text">{bolos.length}</strong><em>Department watch</em></span>
		</button>
		<button class="kpi" onclick={() => navigate("Roster")}>
			<span class="kpi-icon success material-icons">groups</span>
			<span class="kpi-copy"><small>Active units</small><strong class="success-text">{dashboard.activeUnits.count}</strong><em>Currently online</em></span>
		</button>
		<button class="kpi" onclick={() => navigate("Reports")}>
			<span class="kpi-icon accent material-icons">description</span>
			<span class="kpi-copy"><small>Report workload</small><strong>{dashboard.reportsInfo.totalThisWeek}</strong><em>This week{#if dashboard.reportsInfo.changeFromLastWeek !== 0} · {dashboard.reportsInfo.changeFromLastWeek > 0 ? "+" : ""}{dashboard.reportsInfo.changeFromLastWeek}{/if}</em></span>
		</button>
	</section>

	<main class="workspace-grid">
		<section class="workspace-panel priority-panel">
			<div class="panel-heading">
				<div><span class="eyebrow">Priority attention</span><h2>Active warrants</h2></div>
				<button onclick={() => navigate("Warrants")}>View all <span class="material-icons">arrow_forward</span></button>
			</div>
			<div class="panel-scroll priority-scroll">
				{#if warrants.length === 0}
					<div class="empty-row"><span class="material-icons">verified</span>No active warrants</div>
				{:else}
					{#each warrants.slice(0, 4) as warrant}
						<button class="attention-row" onclick={() => openWarrant(warrant.reportid)}>
							<span class="row-icon danger material-icons">gavel</span>
							<span class="row-main"><strong>{warrant.name}</strong><small>Report #{warrant.reportid}{#if warrant.expirydate} · expires {formatDate(warrant.expirydate)}{/if}</small></span>
							<span class="charge-badges">
								{#if warrant.felonies > 0}<em class="danger-badge">{warrant.felonies} felony</em>{/if}
								{#if warrant.misdemeanors > 0}<em class="warning-badge">{warrant.misdemeanors} misdemeanor</em>{/if}
							</span>
							<span class="material-icons row-arrow">chevron_right</span>
						</button>
					{/each}
				{/if}

				<div class="subsection-heading">
					<h2>Active BOLOs</h2>
					<button onclick={() => navigate("BOLOs")}>View all <span class="material-icons">arrow_forward</span></button>
				</div>
				{#if bolos.length === 0}
					<div class="empty-row"><span class="material-icons">notifications_none</span>No active BOLOs</div>
				{:else}
					{#each bolos.slice(0, 4) as bolo}
						<button class="attention-row" onclick={() => navigate("BOLOs")}>
							<span class="row-icon warning material-icons">my_location</span>
							<span class="row-main"><strong>{bolo.name}</strong><small>{bolo.notes || `Report ${bolo.reportId}`}</small></span>
							<em class="type-badge">{bolo.type}</em>
							<span class="material-icons row-arrow">chevron_right</span>
						</button>
					{/each}
				{/if}
			</div>
		</section>

		<section class="workspace-panel unit-panel">
			<div class="panel-heading">
				<div><span class="eyebrow">Unit status</span><h2>{dashboard.activeUnits.count} active units</h2></div>
				<button onclick={() => navigate("Roster")}>Roster <span class="material-icons">arrow_forward</span></button>
			</div>
			<div class="panel-scroll status-panel-body">
				<DispatchStatusWidget detailed />
				{#if impound.held > 0 || impound.outstanding > 0}
					<div class="impound-summary">
						<span class="material-icons">local_shipping</span>
						<div><small>Impound</small><strong>{impound.held} held{#if impound.outstanding > 0} · ${impound.outstanding.toLocaleString()} due{/if}</strong></div>
					</div>
				{/if}
			</div>
		</section>

		<section class="workspace-panel reports-panel">
			<div class="panel-heading">
				<div><span class="eyebrow">Recent reports</span><h2>Department activity</h2></div>
				<button onclick={() => navigate("Reports")}>View all <span class="material-icons">arrow_forward</span></button>
			</div>
			<div class="report-columns" aria-hidden="true"><span>Report</span><span>Officer</span><span>Date</span><span></span></div>
			<div class="panel-scroll report-list">
				{#if reports.length === 0}
					<div class="empty-row"><span class="material-icons">description</span>No recent reports</div>
				{:else}
					{#each reports.slice(0, 7) as report}
						<ReportItem {report} table isExpanded={reportOpened === report.id} onToggle={openReport} onNavigate={viewReport} />
					{/each}
				{/if}
			</div>
		</section>

		<section class="workspace-panel schedule-panel">
			<div class="panel-heading">
				<div><span class="eyebrow">Upcoming</span><h2>Hearings & cases</h2></div>
				<button onclick={() => navigate("Calendar")}>Calendar <span class="material-icons">arrow_forward</span></button>
			</div>
			<div class="panel-scroll schedule-scroll">
				{#if dashboard.upcomingHearings.length === 0}
					<div class="empty-row compact"><span class="material-icons">event_available</span>No upcoming hearings</div>
				{:else}
					{#each dashboard.upcomingHearings.slice(0, 4) as hearing}
						<button class="schedule-row" onclick={() => navigate("Calendar")}>
							<span class="date-block"><strong>{formatDate(hearing.scheduled_at).slice(0, 5)}</strong><small>{formatTime(hearing.scheduled_at)}</small></span>
							<span class="row-main"><strong>{hearing.title}</strong><small>{hearing.location || hearing.defendant_name || "Court calendar"}</small></span>
							<span class="material-icons row-arrow">chevron_right</span>
						</button>
					{/each}
				{/if}

				<div class="subsection-heading case-heading">
					<h2>Open cases</h2>
					<button onclick={() => navigate("Cases")}>View all <span class="material-icons">arrow_forward</span></button>
				</div>
				{#if dashboard.openCases.length === 0}
					<div class="empty-row compact"><span class="material-icons">folder_open</span>No open investigations</div>
				{:else}
					{#each dashboard.openCases.slice(0, 3) as item}
						<button class="case-row" onclick={() => navigate("Cases")}>
							<span class="case-priority" class:high={item.priority === "high"}></span>
							<span class="row-main"><strong>{item.case_number} · {item.title}</strong><small>{item.status === "in_progress" ? "In progress" : "Open investigation"}</small></span>
							<span class="material-icons row-arrow">chevron_right</span>
						</button>
					{/each}
				{/if}
			</div>
		</section>
	</main>

</div>

<style>
	.command-dashboard { height: 100%; min-height: 0; display: flex; flex-direction: column; overflow: hidden; color: rgba(255,255,255,.88); background: radial-gradient(circle at 42% 8%, #141a21 0, #0e1319 42%, #0b1016 100%); }
	button { color: inherit; }
	.dashboard-header { min-height: 72px; display: grid; grid-template-columns: auto minmax(240px, 1fr) auto; align-items: center; gap: 28px; padding: 8px 28px; border-bottom: 1px solid rgba(255,255,255,.065); background: #0e1319; }
	.page-heading h1 { margin: 0; font-size: 21px; line-height: 1.1; letter-spacing: -.35px; color: rgba(255,255,255,.94); }
	.heading-meta { display: flex; align-items: center; gap: 8px; margin-top: 4px; font-size: 9px; color: rgba(255,255,255,.42); }
	.shift-pill { padding: 2px 6px; border-radius: 3px; background: rgba(var(--accent-rgb),.13); color: rgba(var(--accent-text-rgb),.82); font-size: 8px; font-weight: 750; letter-spacing: .45px; text-transform: uppercase; }
	.bulletin-line { display: flex; align-items: center; gap: 9px; min-width: 0; justify-self: center; width: min(100%, 580px); }
	.bulletin-line > .material-icons { font-size: 17px; color: #e6aa35; }
	.bulletin-copy { min-width: 0; display: flex; flex-direction: column; }
	.eyebrow { color: rgba(255,255,255,.38); font-size: 9px; font-weight: 750; letter-spacing: .75px; text-transform: uppercase; }
	.bulletin-message { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: rgba(255,255,255,.64); font-size: 11px; }
	.header-actions { display: flex; align-items: center; gap: 6px; }
	.callsign-control, .shift-button, .signout-button { height: 34px; display: inline-flex; align-items: center; justify-content: center; border: 1px solid rgba(255,255,255,.08); border-radius: 5px; transition: .15s ease; }
	.callsign-control { gap: 7px; padding: 0 9px; background: rgba(255,255,255,.02); }
	.callsign-control > .material-icons { font-size: 15px; color: rgba(255,255,255,.48); }
	.callsign-control span:last-child { display: flex; flex-direction: column; color: rgba(var(--accent-text-rgb),.9); font-size: 9px; font-weight: 700; text-align: left; }
	.callsign-control small { color: rgba(255,255,255,.32); font-size: 7px; text-transform: uppercase; letter-spacing: .55px; }
	.shift-button { gap: 7px; padding: 0 13px; border-color: rgba(var(--accent-rgb),.55); background: rgba(var(--accent-rgb),.78); color: white; font-size: 10px; font-weight: 700; }
	.shift-button .material-icons, .signout-button .material-icons { font-size: 15px; }
	.signout-button { width: 34px; background: rgba(255,255,255,.02); color: rgba(255,255,255,.42); }
	.signout-button:hover { background: rgba(255,255,255,.055); border-color: rgba(255,255,255,.14); }
	.shift-button:hover { background: rgba(var(--accent-rgb),.95); }

	.kpi-strip { display: grid; grid-template-columns: repeat(4, 1fr); min-height: 86px; margin: 0 28px 12px; border: 1px solid rgba(255,255,255,.07); border-radius: 7px; background: rgba(255,255,255,.022); overflow: hidden; }
	.kpi { display: flex; align-items: center; gap: 11px; padding: 10px 16px; background: transparent; border: 0; border-right: 1px solid rgba(255,255,255,.07); text-align: left; cursor: pointer; }
	.kpi:last-child { border-right: 0; }
	.kpi:hover { background: rgba(255,255,255,.025); }
	.kpi-icon, .row-icon { display: grid; place-items: center; flex: 0 0 auto; }
	.kpi-icon { width: 42px; height: 42px; border-radius: 50%; font-size: 20px; }
	.kpi-icon.danger, .row-icon.danger { color: #f16d6d; background: rgba(239,68,68,.13); }
	.kpi-icon.warning, .row-icon.warning { color: #e8a62f; background: rgba(245,158,11,.12); }
	.kpi-icon.success { color: #4bd27e; background: rgba(34,197,94,.12); }
	.kpi-icon.accent { color: rgba(var(--accent-text-rgb),.9); background: rgba(var(--accent-rgb),.14); }
	.kpi-copy { display: grid; grid-template-columns: auto auto; align-items: baseline; column-gap: 8px; min-width: 0; }
	.kpi-copy small { grid-column: 1 / -1; color: rgba(255,255,255,.47); font-size: 9px; font-weight: 750; letter-spacing: .65px; text-transform: uppercase; }
	.kpi-copy strong { font-size: 22px; line-height: 1.1; color: rgba(var(--accent-text-rgb),.95); font-variant-numeric: tabular-nums; }
	.kpi-copy em { color: rgba(255,255,255,.38); font-size: 9.5px; font-style: normal; white-space: nowrap; }
	.danger-text { color: #f16d6d !important; } .warning-text { color: #e8a62f !important; } .success-text { color: #4bd27e !important; }

	.workspace-grid { flex: 1; min-height: 0; display: grid; grid-template-columns: minmax(0, 1.3fr) minmax(360px, 1fr); grid-template-rows: minmax(0, 1.2fr) minmax(0, .95fr); grid-template-areas: "priority unit" "reports schedule"; gap: 12px; padding: 0 28px 14px; }
	.workspace-panel { min-height: 0; display: flex; flex-direction: column; background: rgba(255,255,255,.018); border: 1px solid rgba(255,255,255,.07); border-radius: 7px; overflow: hidden; }
	.priority-panel { grid-area: priority; } .unit-panel { grid-area: unit; } .reports-panel { grid-area: reports; } .schedule-panel { grid-area: schedule; }
	.panel-heading, .subsection-heading { display: flex; align-items: center; justify-content: space-between; gap: 14px; flex-shrink: 0; }
	.panel-heading { min-height: 43px; padding: 8px 12px; border-bottom: 1px solid rgba(255,255,255,.065); }
	.panel-heading h2, .subsection-heading h2 { margin: 1px 0 0; color: rgba(255,255,255,.88); font-size: 12px; font-weight: 680; }
	.panel-heading button, .subsection-heading button { display: inline-flex; align-items: center; gap: 4px; padding: 4px; background: transparent; border: 0; color: rgba(var(--accent-text-rgb),.78); font-size: 9.5px; cursor: pointer; }
	.panel-heading button .material-icons, .subsection-heading button .material-icons { font-size: 11px; }
	.panel-heading button:hover, .subsection-heading button:hover { color: rgba(var(--accent-text-rgb),1); }
	.panel-scroll { flex: 1; min-height: 0; overflow-y: auto; scrollbar-width: thin; scrollbar-color: rgba(255,255,255,.1) transparent; }
	.priority-scroll { padding: 2px 10px 8px; }
	.attention-row, .schedule-row, .case-row { width: 100%; display: flex; align-items: center; gap: 9px; padding: 7px 3px; background: transparent; border: 0; border-bottom: 1px solid rgba(255,255,255,.055); text-align: left; cursor: pointer; }
	.attention-row:hover, .schedule-row:hover, .case-row:hover { background: rgba(255,255,255,.022); }
	.row-icon { width: 26px; height: 26px; border-radius: 50%; font-size: 14px; }
	.row-main { min-width: 0; display: flex; flex: 1; flex-direction: column; }
	.row-main strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: rgba(255,255,255,.84); font-size: 11px; font-weight: 580; }
	.row-main small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: rgba(255,255,255,.38); font-size: 9px; }
	.row-arrow { flex: 0 0 auto; color: rgba(255,255,255,.18); font-size: 14px; }
	.charge-badges { display: flex; gap: 4px; }
	.charge-badges em, .type-badge { padding: 2px 5px; border-radius: 3px; font-size: 7px; font-style: normal; font-weight: 750; text-transform: uppercase; }
	.danger-badge { color: #f38b8b; background: rgba(239,68,68,.12); } .warning-badge, .type-badge { color: #e7ad45; background: rgba(245,158,11,.12); }
	.subsection-heading { min-height: 34px; margin-top: 3px; padding: 6px 3px 4px; border-bottom: 1px solid rgba(255,255,255,.07); }
	.empty-row { min-height: 50px; display: flex; align-items: center; justify-content: center; gap: 7px; color: rgba(255,255,255,.3); font-size: 9px; }
	.empty-row .material-icons { font-size: 15px; color: rgba(255,255,255,.22); }
	.empty-row.compact { min-height: 40px; }

	.status-panel-body { padding: 7px 12px 10px; }
	.impound-summary { display: flex; align-items: center; gap: 9px; margin-top: 8px; padding: 9px 0 2px; border-top: 1px solid rgba(255,255,255,.07); }
	.impound-summary > .material-icons { width: 26px; height: 26px; display: grid; place-items: center; border-radius: 50%; background: rgba(245,158,11,.1); color: #e7ad45; font-size: 14px; }
	.impound-summary div { display: flex; flex-direction: column; } .impound-summary small { color: rgba(255,255,255,.32); font-size: 8px; text-transform: uppercase; } .impound-summary strong { color: rgba(255,255,255,.7); font-size: 9px; font-weight: 550; }

	.report-columns { display: grid; grid-template-columns: minmax(0,1fr) 130px 90px 48px; padding: 5px 10px; border-bottom: 1px solid rgba(255,255,255,.045); color: rgba(255,255,255,.25); font-size: 7.5px; font-weight: 700; text-transform: uppercase; letter-spacing: .55px; }
	.report-list { padding: 0 5px 5px; }
	.schedule-scroll { padding: 3px 10px 8px; }
	.date-block { width: 44px; display: flex; flex: 0 0 auto; flex-direction: column; align-items: center; padding: 4px 2px; border: 1px solid rgba(var(--accent-rgb),.16); border-radius: 4px; background: rgba(var(--accent-rgb),.07); }
	.date-block strong { color: rgba(var(--accent-text-rgb),.86); font-size: 9px; } .date-block small { color: rgba(255,255,255,.34); font-size: 7px; }
	.case-heading { margin-top: 5px; }
	.case-row { padding-left: 3px; }
	.case-priority { width: 3px; height: 24px; border-radius: 2px; background: #e8a62f; } .case-priority.high { background: #ef5555; }

	@media (max-width: 1150px) {
		.dashboard-header { grid-template-columns: auto 1fr; gap: 16px; }
		.bulletin-line { display: none; }
		.header-actions { justify-self: end; }
		.workspace-grid { grid-template-columns: minmax(0,1.45fr) minmax(245px,.8fr); }
		.charge-badges { display: none; }
	}
</style>
