<script lang="ts">
	// Inline hover tooltip rendered into <body> so it is never clipped by a
	// scrolling/overflow parent (same idea as the dashboard MOTD tooltip, but
	// floated to body and shown below the target so it never covers neighbours).
	function tip(node: HTMLElement, text: string | undefined) {
		let el: HTMLDivElement | null = null;
		let cur = text;
		function place(e: MouseEvent) {
			if (!el) return;
			const t = el.getBoundingClientRect();
			let x = e.clientX + 14;
			let y = e.clientY + 16;
			if (x + t.width > window.innerWidth - 4) x = e.clientX - t.width - 14;
			if (y + t.height > window.innerHeight - 4) y = e.clientY - t.height - 16;
			el.style.left = `${Math.max(4, x)}px`;
			el.style.top = `${Math.max(4, y)}px`;
		}
		function show(e: MouseEvent) {
			if (!cur || el) return;
			el = document.createElement("div");
			el.textContent = cur;
			el.style.cssText = "position:fixed;z-index:99999;background:#111113;color:rgba(255,255,255,0.92);padding:6px 9px;border-radius:5px;font-size:11px;font-weight:500;line-height:1.4;max-width:240px;white-space:normal;word-break:break-word;border:1px solid rgba(255,255,255,0.12);box-shadow:0 8px 24px rgba(0,0,0,0.6);pointer-events:none;";
			document.body.appendChild(el);
			place(e);
		}
		function move(e: MouseEvent) { if (el) place(e); }
		function hide() { if (el) { el.remove(); el = null; } }
		node.addEventListener("mouseenter", show);
		node.addEventListener("mousemove", move);
		node.addEventListener("mouseleave", hide);
		return {
			update(v: string | undefined) { cur = v; if (el && !v) hide(); },
			destroy() { hide(); node.removeEventListener("mouseenter", show); node.removeEventListener("mousemove", move); node.removeEventListener("mouseleave", hide); },
		};
	}

	import { onMount } from "svelte";
	import { formatDate } from "../utils/datetime";
	import { fetchNui } from "../utils/fetchNui";
	import { useNuiEvent } from "../utils/useNuiEvent";
	import { debugData } from "../utils/debugData";
	import { isEnvBrowser } from "../utils/misc";
	import { NUI_EVENTS } from "../constants/nuiEvents";
	import { globalNotifications } from "../services/notificationService.svelte";
	import {
		getPromotionActionState,
		loadRosterManagementData,
		personnelActionMessage,
	} from "../utils/rosterManagement";
	import type { AuthService } from "../services/authService.svelte";
	import ActivityTimeline from "../components/ActivityTimeline.svelte";

	let { authService, tabService }: { authService?: AuthService; tabService?: any } = $props();

	interface Officer {
		id: string;
		callsign: string;
		firstName: string;
		lastName: string;
		rank: string;
		department?: string;
		departmentLabel?: string;
		status: "On Duty" | "Off Duty";
		certifications: string[];
		badgeNumber: string;
		citizenid?: string;
		radioChannel?: number;
		employmentStatus?: string;
		assignments?: string[];
		primaryAssignment?: string;
		compartments?: string[];
		grants?: string[];
		restrictions?: string[];
	}

	interface ActiveUnit {
		id: string;
		badgeNumber: string;
		firstName: string;
		lastName: string;
		callsign: string;
	}

	interface OfficerTag {
		id: number;
		name: string;
		color: string;
		description?: string;
	}

	interface JobGrade {
		grade: number;
		name: string;
		isBoss: boolean;
	}

	interface TaskForceMember {
		taskForceId: string;
		citizenid: string;
		agency: string;
		grade: number;
		badge: string;
		callsign: string;
		role: string;
		status: string;
		startsAt?: string;
		expiresAt?: string;
		reason?: string;
	}

	interface TaskForce {
		id: string;
		name: string;
		appointingAgency: string;
		status: string;
		startsAt?: string;
		expiresAt?: string;
		reason?: string;
		scope: {
			agencies?: string[];
			permissions?: string[];
			recordTypes?: string[];
			caseIds?: number[];
			reportIds?: number[];
			incidentIds?: string[];
		};
		members: TaskForceMember[];
	}

	let officers = $state<Officer[]>([]);
	let activeUnits = $state<ActiveUnit[]>([]);
	let isLoading = $state(false);
	let searchQuery = $state("");
	let sortColumn = $state<string>("");
	let sortDirection = $state<"asc" | "desc">("asc");

	// Certification modal state
	let selectedOfficer = $state<Officer | null>(null);
	let availableTags = $state<OfficerTag[]>([]);
	let selectedCerts = $state<string[]>([]);
	let isSavingCerts = $state(false);
	let showCertModal = $state(false);
	let certExpiresAt = $state("");

	// Boss panel state
	let showBossPanel = $state(false);
	let isBossPanelLoading = $state(false);
	let bossPanelTab = $state<"rank" | "callsign" | "access" | "certs" | "ppr" | "fto" | "ia_history" | "activity">("rank");
	let iaHistory = $state<Array<{ id: number; complaint_number: string; category: string; status: string; created_at: string }>>([]);
	let iaHistoryLoading = $state(false);
	let pprHistory = $state<Array<{ id: number; ppr_number: string; category: string; title: string; author_name: string; incident_date?: string; created_at: string }>>([]);
	let pprHistoryLoading = $state(false);
	let ftoHistory = $state<Array<{ id: number; fto_number: string; status: string; trainer_name: string; trainee_name: string; phase_name?: string; start_date?: string; dor_count?: number; latest_rating?: number; created_at: string }>>([]);
	let ftoHistoryLoading = $state(false);
	let jobGrades = $state<JobGrade[]>([]);
	let selectedGrade = $state<number | null>(null);
	let editCallsign = $state("");
	let isSavingBoss = $state(false);
	let showFireConfirm = $state(false);
	let actionReason = $state("");
	let editBadge = $state("");
	let editAssignment = $state("patrol");
	let assignmentPrimary = $state(false);
	let assignmentActive = $state(true);
	let editStatus = $state("active");
	let transferAgency = $state("brpd");
	let transferGrades = $state<JobGrade[]>([]);
	let transferGrade = $state<number | null>(null);
	let editCompartment = $state("internal_affairs");
	let compartmentActive = $state(true);
	let compartmentExpiresAt = $state("");
	let editPermission = $state("records.review");
	let permissionExpiresAt = $state("");
	let restrictionActive = $state(true);
	let restrictionExpiresAt = $state("");
	let showHireModal = $state(false);
	let hireCitizenId = $state("");
	let hireBadge = $state("");
	let hireCallsign = $state("");
	let hireReason = $state("");
	let showTaskForceModal = $state(false);
	let taskForceCreating = $state(false);
	let taskForces = $state<TaskForce[]>([]);
	let selectedTaskForceId = $state("");
	let taskForceLoading = $state(false);
	let taskForceSaving = $state(false);
	let taskForceName = $state("");
	let taskForceExpiresAt = $state("");
	let taskForceReason = $state("");
	let taskForceAgencies = $state<string[]>(["brpd", "ebrso"]);
	let taskForcePermissions = $state<string[]>(["records.view", "records.supplement", "evidence.view", "dispatch.view"]);
	let taskForceRecordTypes = $state<string[]>(["cases", "reports"]);
	let taskForceCaseIds = $state("");
	let taskForceReportIds = $state("");
	let taskForceIncidentIds = $state("");
	let taskForceMemberCitizenId = $state("");
	let taskForceMemberRole = $state("member");
	let taskForceMemberStatus = $state("active");
	let taskForceMemberExpiresAt = $state("");
	let taskForceMemberReason = $state("");
	let taskForceStatus = $state("suspended");
	let taskForceStatusReason = $state("");

	const taskForcePermissionOptions = [
		"records.view", "records.create", "records.supplement", "records.review", "records.lifecycle",
		"evidence.view", "evidence.custody", "evidence.transfer", "evidence.submit", "evidence.release",
		"dispatch.view", "dispatch.assign_other",
	];

	let canManageCerts = $derived(authService?.hasPermission("roster_manage_certifications") ?? false);
	let canHireOfficers = $derived(authService?.hasPermission("roster_hire_officers") ?? false);
	let canManageOfficers = $derived(authService?.hasPermission("roster_manage_officers") ?? false);
	let canViewTaskForces = $derived(authService?.hasPermission("taskforces_view") ?? false);
	let canManageTaskForces = $derived(authService?.hasPermission("taskforces_manage") ?? false);
	let canOpenPanel = $derived(canManageCerts || canManageOfficers);
	let selectedGradeName = $derived(jobGrades.find((grade) => grade.grade === selectedGrade)?.name);
	let promotionAction = $derived(
		getPromotionActionState(selectedGrade, actionReason, selectedGradeName, isSavingBoss, isBossPanelLoading),
	);
	let selectedTaskForce = $derived(taskForces.find((taskForce) => taskForce.id === selectedTaskForceId) || null);

	// Phase 2: EMS-aware terminology. The roster is shared UI but the wording
	// should match the caller's domain (police "Officer" vs EMS "Personnel").
	let isEmsDomain = $derived((authService?.jobType ?? "leo") === "ems");
	let term = $derived({
		member: isEmsDomain ? "Personnel" : "Officer",
		members: isEmsDomain ? "Personnel" : "Officers",
		memberLower: isEmsDomain ? "member" : "officer",
		membersLower: isEmsDomain ? "members" : "officers",
		management: isEmsDomain ? "Personnel Management" : "Officer Management",
		terminate: isEmsDomain ? "Terminate Member" : "Terminate Officer",
		removeHint: isEmsDomain
			? "Remove this person from the department. This sets their job to unemployed."
			: "Remove this officer from the department. This sets their job to unemployed.",
	});

	let filteredOfficers = $derived.by(() => {
		const query = searchQuery.trim().toLowerCase();
		let filtered = !query
			? officers
			: officers.filter(({ callsign, firstName, lastName, rank }) =>
					[callsign, firstName, lastName, rank].some((val) =>
						val.toLowerCase().includes(query),
					),
				);

		if (sortColumn) {
			filtered = [...filtered].sort((a, b) => {
				let aVal: string | number = "";
				let bVal: string | number = "";

				switch (sortColumn) {
					case "name":
						aVal = `${a.firstName} ${a.lastName}`;
						bVal = `${b.firstName} ${b.lastName}`;
						break;
					case "callsign":
						aVal = a.callsign;
						bVal = b.callsign;
						break;
					case "rank":
						aVal = a.rank;
						bVal = b.rank;
						break;
					case "status":
						aVal = a.status;
						bVal = b.status;
						break;
				}

				if (typeof aVal === "string" && typeof bVal === "string") {
					const result = aVal.localeCompare(bVal);
					return sortDirection === "asc" ? result : -result;
				}
				return 0;
			});
		}

		return filtered;
	});

	onMount(() => {
		if (isEnvBrowser()) {
			officers = [
				{
					id: "1",
					callsign: "401",
					firstName: "John",
					lastName: "Smith",
					rank: "Chief of Police",
					department: "lspd",
					status: "On Duty",
					certifications: ["FTO", "SWAT", "Interceptor"],
					badgeNumber: "1001",
					citizenid: "ABC12345",
					radioChannel: 1,
				},
				{
					id: "2",
					callsign: "455",
					firstName: "Jane",
					lastName: "Doe",
					rank: "Lieutenant",
					department: "lspd",
					status: "On Duty",
					certifications: ["Air Certified", "FTO"],
					badgeNumber: "1002",
					citizenid: "DEF67890",
					radioChannel: 1,
				},
				{
					id: "3",
					callsign: "474",
					firstName: "Mike",
					lastName: "Johnson",
					rank: "Sergeant",
					department: "bcso",
					status: "Off Duty",
					certifications: ["SWAT"],
					badgeNumber: "1003",
					citizenid: "GHI11111",
					radioChannel: 0,
				},
				{
					id: "4",
					callsign: "402",
					firstName: "Sarah",
					lastName: "Wilson",
					rank: "Officer",
					department: "lspd",
					status: "On Duty",
					certifications: [],
					badgeNumber: "1004",
					citizenid: "JKL22222",
					radioChannel: 2,
				},
				{
					id: "5",
					callsign: "472",
					firstName: "David",
					lastName: "Brown",
					rank: "Detective",
					department: "sahp",
					status: "Off Duty",
					certifications: ["FTO"],
					badgeNumber: "1005",
					citizenid: "MNO33333",
					radioChannel: 0,
				},
			];

			activeUnits = [
				{ id: "1", badgeNumber: "1001", firstName: "John", lastName: "Smith", callsign: "401" },
				{ id: "2", badgeNumber: "1002", firstName: "Jane", lastName: "Doe", callsign: "455" },
				{ id: "4", badgeNumber: "1004", firstName: "Sarah", lastName: "Wilson", callsign: "402" },
			];

			availableTags = [
				{ id: 1, name: "SWAT", color: "#3b82f6" },
				{ id: 2, name: "FTO", color: "#10b981" },
				{ id: 3, name: "Detective", color: "#8b5cf6" },
				{ id: 4, name: "K9 Certified", color: "#06b6d4" },
				{ id: 5, name: "Air Certified", color: "#ec4899" },
				{ id: 6, name: "Command", color: "#ef4444" },
			];
		} else {
			loadRoster();
			loadOfficerTags();
		}
	});

	useNuiEvent<Officer[]>(NUI_EVENTS.ROSTER.GET_ROSTER, (data: Officer[]) => {
		officers = Array.isArray(data) ? data : [];
	});

	useNuiEvent<ActiveUnit[]>(
		NUI_EVENTS.ROSTER.GET_ACTIVE_UNITS,
		(data: ActiveUnit[]) => {
			activeUnits = Array.isArray(data) ? data : [];
		},
	);

	async function loadRoster() {
		try {
			isLoading = true;
			const response = await fetchNui(NUI_EVENTS.ROSTER.GET_ROSTER);
			officers = Array.isArray(response.roster) ? response.roster : [];
			activeUnits = Array.isArray(response.activeUnits)
				? response.activeUnits
				: [];
		} catch (error) {
			globalNotifications.error("Failed to load roster");
			officers = [];
		} finally {
			isLoading = false;
		}
	}

	async function loadOfficerTags() {
		if (isEnvBrowser()) return;
		try {
			const tags = await fetchNui(NUI_EVENTS.ROSTER.GET_OFFICER_TAGS);
			availableTags = Array.isArray(tags) ? tags : [];
		} catch {
			availableTags = [];
		}
	}

	async function loadJobGrades(department: string) {
		if (isEnvBrowser()) {
			// Dev mock: derive grades from the officer mock data ranks
			const uniqueRanks = [...new Set(officers.map((o) => o.rank))];
			jobGrades = uniqueRanks.map((name, i) => ({
				grade: i,
				name,
				isBoss: i === uniqueRanks.length - 1,
			}));
			return;
		}
		try {
			const grades = await fetchNui<JobGrade[]>(NUI_EVENTS.ROSTER.GET_JOB_GRADES, { job: department });
			jobGrades = Array.isArray(grades) ? grades : [];
		} catch {
			jobGrades = [];
		}
	}

	async function loadTransferGrades(agency: string) {
		if (isEnvBrowser()) {
			transferGrades = jobGrades;
			transferGrade = null;
			return;
		}
		try {
			const grades = await fetchNui<JobGrade[]>(NUI_EVENTS.ROSTER.GET_JOB_GRADES, { job: agency });
			transferGrades = Array.isArray(grades) ? grades : [];
		} catch {
			transferGrades = [];
		}
		transferGrade = null;
	}

	function databaseDate(value: string): string | null {
		if (!value) return null;
		return value.replace("T", " ") + (value.length === 16 ? ":00" : "");
	}

	function officerHasCompartment(officer: Officer | null, compartment: string): boolean {
		return (officer?.compartments || []).some((value) => value === compartment || value.endsWith(`:${compartment}`));
	}

	function handleSort(column: string) {
		if (sortColumn === column) {
			sortDirection = sortDirection === "asc" ? "desc" : "asc";
		} else {
			sortColumn = column;
			sortDirection = "asc";
		}
	}

	function getSortIndicator(column: string): string {
		if (sortColumn !== column) return "";
		return sortDirection === "asc" ? " ↑" : " ↓";
	}

	function refreshData() {
		if (!isEnvBrowser()) {
			loadRoster();
		}
	}

	async function openOfficerPanel(officer: Officer) {
		if (!canOpenPanel) return;

		selectedOfficer = officer;
		selectedCerts = [...(officer.certifications || [])];
		certExpiresAt = "";
		editCallsign = officer.callsign || "";
		editBadge = officer.badgeNumber || "";
		editStatus = officer.employmentStatus || "active";
		editAssignment = officer.primaryAssignment || officer.assignments?.[0] || "patrol";
		assignmentPrimary = officer.primaryAssignment === editAssignment;
		assignmentActive = true;
		transferAgency = officer.department === "brpd" ? "ebrso" : "brpd";
		transferGrade = null;
		editCompartment = "internal_affairs";
		compartmentActive = !officerHasCompartment(officer, editCompartment);
		compartmentExpiresAt = "";
		permissionExpiresAt = "";
		restrictionExpiresAt = "";
		actionReason = "";
		selectedGrade = null;
		showFireConfirm = false;

		if (canManageOfficers) {
			// Open boss panel immediately for instant responsiveness
			bossPanelTab = "rank";
			showBossPanel = true;
			isBossPanelLoading = true;
			try {
				await loadRosterManagementData(
					loadOfficerTags,
					() => loadJobGrades(officer.department || "police"),
					() => loadTransferGrades(transferAgency),
				);
			} finally {
				isBossPanelLoading = false;
			}
		} else {
			// Fall back to cert-only modal
			showCertModal = true;
			await loadOfficerTags();
		}
	}

	function closeBossPanel() {
		showBossPanel = false;
		showFireConfirm = false;
		selectedOfficer = null;
		selectedCerts = [];
		certExpiresAt = "";
		actionReason = "";
		editCallsign = "";
		editBadge = "";
		selectedGrade = null;
		jobGrades = [];
	}

	function closeCertModal() {
		showCertModal = false;
		selectedOfficer = null;
		selectedCerts = [];
		certExpiresAt = "";
		actionReason = "";
	}

	function toggleCert(tagName: string) {
		if (selectedCerts.includes(tagName)) {
			selectedCerts = selectedCerts.filter((c) => c !== tagName);
		} else {
			selectedCerts = [...selectedCerts, tagName];
		}
	}

	async function saveCertifications() {
		if (!selectedOfficer?.citizenid || actionReason.trim().length < 3) return;
		isSavingCerts = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(
				NUI_EVENTS.ROSTER.UPDATE_OFFICER_CERTIFICATIONS,
				{
					citizenid: selectedOfficer.citizenid,
					certifications: selectedCerts,
					expiresAt: databaseDate(certExpiresAt),
					reason: actionReason.trim(),
				},
			);
			if (response?.success) {
				const idx = officers.findIndex((o) => o.citizenid === selectedOfficer!.citizenid);
				if (idx !== -1) {
					officers[idx].certifications = [...selectedCerts];
				}
				globalNotifications.success(`Updated certifications for ${selectedOfficer.firstName} ${selectedOfficer.lastName}`);
				if (showBossPanel) {
					// Stay on boss panel, just show success
				} else {
					closeCertModal();
				}
			} else {
				globalNotifications.error(response?.message || "Failed to update certifications");
			}
		} catch {
			globalNotifications.error("Failed to update certifications");
		} finally {
			isSavingCerts = false;
		}
	}

	async function promoteOfficer() {
		if (!selectedOfficer?.citizenid || selectedGrade === null || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(
				NUI_EVENTS.ROSTER.PROMOTE_OFFICER,
				{
					citizenid: selectedOfficer.citizenid,
					job: selectedOfficer.department || "police",
					grade: selectedGrade,
					reason: actionReason.trim(),
				},
			);
			if (response?.success) {
				const gradeName = jobGrades.find((g) => g.grade === selectedGrade)?.name || `Grade ${selectedGrade}`;
				const idx = officers.findIndex((o) => o.citizenid === selectedOfficer!.citizenid);
				if (idx !== -1) {
					officers[idx].rank = gradeName;
				}
				selectedOfficer.rank = gradeName;
				selectedGrade = null;
				globalNotifications.success(response.message || `Rank updated to ${gradeName}`);
			} else {
				globalNotifications.error(personnelActionMessage(response?.message));
			}
		} catch {
			globalNotifications.error(personnelActionMessage("service_unavailable"));
		} finally {
			isSavingBoss = false;
		}
	}

	let deleteUserData = $state(false);

	async function fireOfficer() {
		if (!selectedOfficer?.citizenid || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(
				NUI_EVENTS.ROSTER.FIRE_OFFICER,
				{ citizenid: selectedOfficer.citizenid, deleteData: deleteUserData, reason: actionReason.trim() },
			);
			if (response?.success) {
				globalNotifications.success(response.message || `${term.member} has been terminated`);
				closeBossPanel();
				await loadRoster();
			} else {
				globalNotifications.error(response?.message || `Failed to terminate ${term.memberLower}`);
			}
		} catch {
			globalNotifications.error(`Failed to terminate ${term.memberLower}`);
		} finally {
			isSavingBoss = false;
			showFireConfirm = false;
			deleteUserData = false;
		}
	}

	async function loadIAHistory() {
		if (!selectedOfficer) return;
		iaHistoryLoading = true;
		try {
			const officerName = `${selectedOfficer.firstName} ${selectedOfficer.lastName}`;
			const result = await fetchNui<Array<{ id: number; complaint_number: string; category: string; status: string; created_at: string }>>(
				NUI_EVENTS.IA.GET_IA_HISTORY_FOR_OFFICER,
				{ officerName, officerCid: selectedOfficer.citizenid },
				[]
			);
			iaHistory = Array.isArray(result) ? result : [];
		} catch {
			iaHistory = [];
		}
		iaHistoryLoading = false;
	}

	function formatIAStatus(status: string): string {
		return status.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
	}

	function getIAStatusClass(status: string): string {
		switch (status) {
			case 'open': return 'pill-blue';
			case 'under_review': return 'pill-orange';
			case 'investigated': return 'pill-yellow';
			case 'sustained': return 'pill-red';
			case 'exonerated': return 'pill-green';
			default: return 'pill-gray';
		}
	}

	async function loadOfficerPPR() {
		if (!selectedOfficer?.citizenid) return;
		pprHistoryLoading = true;
		try {
			const result = await fetchNui<Array<{ id: number; ppr_number: string; category: string; title: string; author_name: string; incident_date?: string; created_at: string }>>(
				NUI_EVENTS.PPR.GET_OFFICER_PPR_HISTORY,
				{ officerCitizenId: selectedOfficer.citizenid },
				[]
			);
			pprHistory = Array.isArray(result) ? result : [];
		} catch {
			pprHistory = [];
		}
		pprHistoryLoading = false;
	}

	async function loadOfficerFTO() {
		if (!selectedOfficer?.citizenid) return;
		ftoHistoryLoading = true;
		try {
			const result = await fetchNui<Array<any>>(
				NUI_EVENTS.FTO.GET_OFFICER_FTO_HISTORY,
				{ officerCitizenId: selectedOfficer.citizenid },
				[]
			);
			ftoHistory = Array.isArray(result) ? result : [];
		} catch {
			ftoHistory = [];
		}
		ftoHistoryLoading = false;
	}

	function getFTOStatusClass(status: string): string {
		switch (status) {
			case 'active': return 'status-active';
			case 'completed': return 'status-completed';
			case 'failed': return 'status-failed';
			case 'suspended': return 'status-suspended';
			default: return '';
		}
	}

	function getPPRCategoryClass(category: string): string {
		switch (category) {
			case 'positive': return 'pill-green';
			case 'coaching': return 'pill-orange';
			case 'disciplinary': return 'pill-red';
			default: return 'pill-gray';
		}
	}

	function formatPPRCategory(category: string): string {
		return category.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
	}

	function formatDateShort(dateStr: string): string {
		return formatDate(dateStr, "");
	}

	async function saveCallsign() {
		if (!selectedOfficer?.citizenid || !editCallsign.trim() || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(
				NUI_EVENTS.ROSTER.UPDATE_CALLSIGN,
				{
					citizenid: selectedOfficer.citizenid,
					callsign: editCallsign.trim(),
					reason: actionReason.trim(),
				},
			);
			if (response?.success) {
				const idx = officers.findIndex((o) => o.citizenid === selectedOfficer!.citizenid);
				if (idx !== -1) {
					officers[idx].callsign = editCallsign.trim();
				}
				globalNotifications.success(response.message || `Callsign updated to ${editCallsign.trim()}`);
			} else {
				globalNotifications.error(response?.message || "Failed to update callsign");
			}
		} catch {
			globalNotifications.error("Failed to update callsign");
		} finally {
			isSavingBoss = false;
		}
	}

	async function saveBadge() {
		if (!selectedOfficer?.citizenid || !editBadge.trim() || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(NUI_EVENTS.ROSTER.UPDATE_BADGE, {
				citizenid: selectedOfficer.citizenid, badge: editBadge.trim(), reason: actionReason.trim(),
			});
			if (response?.success) {
				selectedOfficer.badgeNumber = editBadge.trim();
				globalNotifications.success(response.message || "Badge number updated");
			} else globalNotifications.error(response?.message || "Failed to update badge number");
		} catch { globalNotifications.error("Failed to update badge number"); }
		finally { isSavingBoss = false; }
	}

	async function saveAssignment() {
		if (!selectedOfficer?.citizenid || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(NUI_EVENTS.ROSTER.UPDATE_ASSIGNMENT, {
				citizenid: selectedOfficer.citizenid, assignment: editAssignment,
				primary: assignmentPrimary, active: assignmentActive, reason: actionReason.trim(),
			});
			if (response?.success) {
				globalNotifications.success(response.message || "Assignment updated");
				await loadRoster();
			}
			else globalNotifications.error(response?.message || "Failed to update assignment");
		} catch { globalNotifications.error("Failed to update assignment"); }
		finally { isSavingBoss = false; }
	}

	async function transferOfficer() {
		if (!selectedOfficer?.citizenid || transferGrade === null || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(NUI_EVENTS.ROSTER.TRANSFER_OFFICER, {
				citizenid: selectedOfficer.citizenid, agency: transferAgency, grade: transferGrade,
				reason: actionReason.trim(),
			});
			if (response?.success) {
				globalNotifications.success(response.message || "Officer transferred");
				closeBossPanel();
				await loadRoster();
			} else globalNotifications.error(response?.message || "Failed to transfer officer");
		} catch { globalNotifications.error("Failed to transfer officer"); }
		finally { isSavingBoss = false; }
	}

	async function saveCompartment() {
		if (!selectedOfficer?.citizenid || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(NUI_EVENTS.ROSTER.UPDATE_COMPARTMENT, {
				citizenid: selectedOfficer.citizenid, compartment: editCompartment, active: compartmentActive,
				expiresAt: databaseDate(compartmentExpiresAt), reason: actionReason.trim(),
			});
			if (response?.success) {
				globalNotifications.success(response.message || "Protected access updated");
				await loadRoster();
			} else globalNotifications.error(response?.message || "Failed to update protected access");
		} catch { globalNotifications.error("Failed to update protected access"); }
		finally { isSavingBoss = false; }
	}

	async function grantTemporaryPermission() {
		if (!selectedOfficer?.citizenid || !permissionExpiresAt || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(NUI_EVENTS.ROSTER.GRANT_PERMISSION, {
				citizenid: selectedOfficer.citizenid, permission: editPermission,
				expiresAt: databaseDate(permissionExpiresAt), reason: actionReason.trim(),
			});
			if (response?.success) globalNotifications.success(response.message || "Temporary permission granted");
			else globalNotifications.error(response?.message || "Failed to grant temporary permission");
		} catch { globalNotifications.error("Failed to grant temporary permission"); }
		finally { isSavingBoss = false; }
	}

	async function saveRestriction() {
		if (!selectedOfficer?.citizenid || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(NUI_EVENTS.ROSTER.RESTRICT_PERMISSION, {
				citizenid: selectedOfficer.citizenid, permission: editPermission, active: restrictionActive,
				expiresAt: databaseDate(restrictionExpiresAt), reason: actionReason.trim(),
			});
			if (response?.success) globalNotifications.success(response.message || "Permission restriction updated");
			else globalNotifications.error(response?.message || "Failed to update permission restriction");
		} catch { globalNotifications.error("Failed to update permission restriction"); }
		finally { isSavingBoss = false; }
	}

	async function saveStatus() {
		if (!selectedOfficer?.citizenid || actionReason.trim().length < 3) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(NUI_EVENTS.ROSTER.UPDATE_STATUS, {
				citizenid: selectedOfficer.citizenid, status: editStatus, reason: actionReason.trim(),
			});
			if (response?.success) globalNotifications.success(response.message || "Employment status updated");
			else globalNotifications.error(response?.message || "Failed to update employment status");
		} catch { globalNotifications.error("Failed to update employment status"); }
		finally { isSavingBoss = false; }
	}

	async function hireOfficer() {
		if ([hireCitizenId, hireBadge, hireCallsign, hireReason].some((value) => value.trim().length < 3)) return;
		isSavingBoss = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>(NUI_EVENTS.ROSTER.HIRE_OFFICER, {
				citizenid: hireCitizenId.trim(), badge: hireBadge.trim(), callsign: hireCallsign.trim(), reason: hireReason.trim(),
			});
			if (response?.success) {
				globalNotifications.success(response.message || "Officer hired");
				showHireModal = false;
				hireCitizenId = ""; hireBadge = ""; hireCallsign = ""; hireReason = "";
				await loadRoster();
			} else globalNotifications.error(response?.message || "Failed to hire officer");
		} catch { globalNotifications.error("Failed to hire officer"); }
		finally { isSavingBoss = false; }
	}

	function toggleTaskForceValue(values: string[], value: string): string[] {
		return values.includes(value) ? values.filter((entry) => entry !== value) : [...values, value];
	}

	function parseTaskForceNumbers(value: string): number[] {
		return [...new Set(value.split(",").map((entry) => Number(entry.trim())).filter((entry) => Number.isInteger(entry) && entry > 0))];
	}

	function parseTaskForceStrings(value: string): string[] {
		return [...new Set(value.split(",").map((entry) => entry.trim()).filter(Boolean))];
	}

	async function loadTaskForces() {
		taskForceLoading = true;
		try {
			const response = await fetchNui<{ success: boolean; taskForces?: TaskForce[]; message?: string }>("getTaskForces", {});
			taskForces = response?.success && Array.isArray(response.taskForces) ? response.taskForces : [];
			if (!response?.success && response?.message) globalNotifications.error(response.message);
			if (!taskForces.some((taskForce) => taskForce.id === selectedTaskForceId)) {
				selectedTaskForceId = taskForces[0]?.id || "";
			}
		} catch {
			taskForces = [];
			globalNotifications.error("Failed to load task forces");
		} finally {
			taskForceLoading = false;
		}
	}

	async function openTaskForces() {
		showTaskForceModal = true;
		taskForceCreating = false;
		await loadTaskForces();
	}

	async function createTaskForce() {
		if (!canManageTaskForces || taskForceName.trim().length < 3 || taskForceReason.trim().length < 3 ||
			!taskForceExpiresAt || taskForceAgencies.length < 2 || taskForcePermissions.length === 0 ||
			(taskForceRecordTypes.length === 0 && !taskForceCaseIds.trim() && !taskForceReportIds.trim() && !taskForceIncidentIds.trim())) return;
		taskForceSaving = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string; taskForce?: { id?: string } }>("createTaskForce", {
				name: taskForceName.trim(),
				expiresAt: databaseDate(taskForceExpiresAt),
				reason: taskForceReason.trim(),
				scope: {
					agencies: taskForceAgencies,
					permissions: taskForcePermissions,
					recordTypes: taskForceRecordTypes,
					caseIds: parseTaskForceNumbers(taskForceCaseIds),
					reportIds: parseTaskForceNumbers(taskForceReportIds),
					incidentIds: parseTaskForceStrings(taskForceIncidentIds),
				},
			});
			if (response?.success) {
				globalNotifications.success(response.message || "Task force created");
				taskForceName = ""; taskForceReason = ""; taskForceExpiresAt = "";
				taskForceCaseIds = ""; taskForceReportIds = ""; taskForceIncidentIds = "";
				await loadTaskForces();
				if (response.taskForce?.id) selectedTaskForceId = response.taskForce.id;
				taskForceCreating = false;
			} else globalNotifications.error(response?.message || "Failed to create task force");
		} catch { globalNotifications.error("Failed to create task force"); }
		finally { taskForceSaving = false; }
	}

	async function saveTaskForceMember() {
		if (!selectedTaskForce || !taskForceMemberCitizenId || taskForceMemberReason.trim().length < 3 ||
			((taskForceMemberStatus === "active" || taskForceMemberStatus === "suspended") && !taskForceMemberExpiresAt)) return;
		taskForceSaving = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>("setTaskForceMember", {
				taskForceId: selectedTaskForce.id,
				citizenid: taskForceMemberCitizenId,
				role: taskForceMemberRole,
				status: taskForceMemberStatus,
				expiresAt: databaseDate(taskForceMemberExpiresAt),
				reason: taskForceMemberReason.trim(),
			});
			if (response?.success) {
				globalNotifications.success(response.message || "Task force membership updated");
				taskForceMemberReason = "";
				await loadTaskForces();
			} else globalNotifications.error(response?.message || "Failed to update task force member");
		} catch { globalNotifications.error("Failed to update task force member"); }
		finally { taskForceSaving = false; }
	}

	async function saveTaskForceStatus() {
		if (!selectedTaskForce || taskForceStatusReason.trim().length < 3) return;
		taskForceSaving = true;
		try {
			const response = await fetchNui<{ success: boolean; message?: string }>("setTaskForceStatus", {
				taskForceId: selectedTaskForce.id,
				status: taskForceStatus,
				reason: taskForceStatusReason.trim(),
			});
			if (response?.success) {
				globalNotifications.success(response.message || "Task force status updated");
				taskForceStatusReason = "";
				await loadTaskForces();
			} else globalNotifications.error(response?.message || "Failed to update task force status");
		} catch { globalNotifications.error("Failed to update task force status"); }
		finally { taskForceSaving = false; }
	}

	function getTagColor(certName: string): string {
		const tag = availableTags.find((t) => t.name === certName);
		return tag?.color || "#6b7280";
	}
	function getTagDescription(certName: string): string {
		return availableTags.find((t) => t.name === certName)?.description || "";
	}
</script>

<div class="roster-page">
	<div class="topbar">
		<input
			type="text"
			placeholder="Search by callsign, name or rank..."
			bind:value={searchQuery}
			class="search-input"
		/>
		<div class="topbar-right">
			<span class="result-count">{filteredOfficers.length} {term.memberLower}{filteredOfficers.length !== 1 ? "s" : ""}</span>
			{#if canHireOfficers && !isEmsDomain}
				<button class="btn-save" onclick={() => showHireModal = true}>Hire Officer</button>
			{/if}
			{#if canViewTaskForces && !isEmsDomain}
				<button class="btn-secondary" onclick={openTaskForces}>Task Forces</button>
			{/if}
			<button class="btn-secondary" onclick={refreshData} disabled={isLoading}>
				{isLoading ? "Loading..." : "Refresh"}
			</button>
		</div>
	</div>

	<div class="content-area">
		<div class="list-panel">
			<div class="table-header">
				<button class="col-header sortable" onclick={() => handleSort("status")}>Status{getSortIndicator("status")}</button>
				<button class="col-header sortable" onclick={() => handleSort("callsign")}>Call Sign{getSortIndicator("callsign")}</button>
				<button class="col-header sortable" onclick={() => handleSort("name")}>Name{getSortIndicator("name")}</button>
				<span class="col-header">Radio Ch.</span>
				<button class="col-header sortable" onclick={() => handleSort("rank")}>Rank{getSortIndicator("rank")}</button>
				<span class="col-header">Dept</span>
				<span class="col-header">Certifications</span>
			</div>

			<div class="table-body">
				{#if isLoading}
					<div class="empty-state">
						<div class="loading-spinner"></div>
						<p>Loading roster...</p>
					</div>
				{:else if filteredOfficers.length === 0}
					<div class="empty-state">
						<p class="empty-title">No {term.members} Found</p>
						<p class="empty-sub">
							{searchQuery
								? `No ${term.membersLower} match your search criteria.`
								: `No ${term.membersLower} are currently in the roster.`}
						</p>
					</div>
				{:else}
					{#each filteredOfficers as officer (officer.id)}
						<div
							class="table-row"
							class:clickable={canOpenPanel}
							onclick={() => openOfficerPanel(officer)}
						>
							<span class="cell-status">
								<span class="status-pill" class:on-duty={officer.status === "On Duty"} class:off-duty={officer.status === "Off Duty"}>
									{officer.status}
								</span>
							</span>
							<span class="cell-callsign">{officer.callsign}</span>
							<span class="cell-name">{officer.firstName} {officer.lastName}</span>
							<span class="cell-radio">
								{#if officer.radioChannel && officer.radioChannel > 0}
									<span class="radio-badge">{officer.radioChannel}</span>
								{:else}
									<span class="cell-muted">-</span>
								{/if}
							</span>
							<span class="cell-rank">{officer.rank}</span>
							<span class="cell-dept">{officer.departmentLabel || officer.department || "-"}</span>
							<span class="cell-certs">
								{#if officer.certifications.length > 0}
									{#each officer.certifications as cert}
										<span class="cert-tag" use:tip={getTagDescription(cert)} style="border-color: {getTagColor(cert)}40; color: {getTagColor(cert)}">{cert}</span>
									{/each}
								{:else}
									<span class="cell-muted">-</span>
								{/if}
							</span>
						</div>
					{/each}
				{/if}
			</div>
		</div>

		<div class="units-panel">
			<div class="units-header">
				<span class="units-label">Active Units</span>
				<span class="units-count">{activeUnits.length}</span>
			</div>

			{#if activeUnits.length === 0}
				<div class="units-empty">No units active</div>
			{:else}
				<div class="units-list">
					{#each activeUnits as unit (unit.id)}
						<div class="unit-row">
							<span class="unit-callsign">{unit.callsign}</span>
							<span class="unit-name">{unit.firstName.charAt(0)}. {unit.lastName}</span>
						</div>
					{/each}
				</div>
			{/if}
		</div>
	</div>
</div>

<!-- Certification Modal (for users without boss panel access) -->
{#if showCertModal && selectedOfficer}
	<!-- svelte-ignore a11y_click_events_have_key_events -->
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="modal-overlay" onclick={closeCertModal}>
		<div class="modal-container" onclick={(e) => e.stopPropagation()}>
			<div class="modal-header">
				<div class="modal-title-area">
					<span class="modal-title">Manage Certifications</span>
					<span class="modal-subtitle">{selectedOfficer.firstName} {selectedOfficer.lastName} - {selectedOfficer.callsign}</span>
				</div>
				<button class="modal-close" onclick={closeCertModal}>
					<span class="material-icons">close</span>
				</button>
			</div>

			<div class="modal-body">
				<label class="boss-label">Written Reason</label>
				<input class="callsign-input" bind:value={actionReason} maxlength="500" placeholder="Required reason for this personnel action" />
				<label class="boss-label">Expiration or Renewal Date</label>
				<input class="callsign-input" type="datetime-local" bind:value={certExpiresAt} />
				<p class="boss-hint">Optional. When supplied, every selected certification is issued or renewed through this date.</p>
				{#if availableTags.length === 0}
					<div class="no-tags">
						<span class="material-icons no-tags-icon">label_off</span>
						<p>No certifications available.</p>
						<p class="no-tags-hint">Create {term.memberLower} tags in Management &gt; Tags</p>
					</div>
				{:else}
					<div class="cert-grid">
						{#each availableTags as tag (tag.id)}
							<button
								class="cert-option"
								class:selected={selectedCerts.includes(tag.name)}
								onclick={() => toggleCert(tag.name)}
								use:tip={tag.description}
								style="--tag-color: {tag.color}"
							>
								<span class="cert-check">
									{#if selectedCerts.includes(tag.name)}
										<span class="material-icons">check_circle</span>
									{:else}
										<span class="material-icons">radio_button_unchecked</span>
									{/if}
								</span>
								<span class="cert-color-dot" style="background: {tag.color}"></span>
								<span class="cert-label">{tag.name}</span>
							</button>
						{/each}
					</div>
				{/if}
			</div>

			<div class="modal-footer">
				<button class="btn-cancel" onclick={closeCertModal}>Cancel</button>
				<button
					class="btn-save"
					onclick={saveCertifications}
					disabled={isSavingCerts || availableTags.length === 0 || actionReason.trim().length < 3}
				>
					{isSavingCerts ? "Saving..." : "Save"}
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Boss Panel Modal -->
{#if showBossPanel && selectedOfficer}
	<!-- svelte-ignore a11y_click_events_have_key_events -->
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<div class="modal-overlay" onclick={closeBossPanel}>
		<div class="boss-panel" onclick={(e) => e.stopPropagation()}>
			<div class="modal-header">
				<div class="modal-title-area">
					<span class="modal-title">{term.management}</span>
					<span class="modal-subtitle">{selectedOfficer.firstName} {selectedOfficer.lastName} &bull; {selectedOfficer.callsign} &bull; {selectedOfficer.rank}</span>
				</div>
				<button class="modal-close" onclick={closeBossPanel}>
					<span class="material-icons">close</span>
				</button>
			</div>

			<div class="boss-tabs">
				<button class="boss-tab" class:active={bossPanelTab === "rank"} onclick={() => { bossPanelTab = "rank"; showFireConfirm = false; }}>
					<span class="material-icons boss-tab-icon">military_tech</span>
					Rank
				</button>
				<button class="boss-tab" class:active={bossPanelTab === "callsign"} onclick={() => { bossPanelTab = "callsign"; showFireConfirm = false; }}>
					<span class="material-icons boss-tab-icon">badge</span>
					Identity
				</button>
				<button class="boss-tab" class:active={bossPanelTab === "access"} onclick={() => { bossPanelTab = "access"; showFireConfirm = false; }}>
					<span class="material-icons boss-tab-icon">admin_panel_settings</span>
					Access
				</button>
				{#if canManageCerts}
					<button class="boss-tab" class:active={bossPanelTab === "certs"} onclick={() => { bossPanelTab = "certs"; showFireConfirm = false; }}>
						<span class="material-icons boss-tab-icon">verified</span>
						Certifications
					</button>
				{/if}
				<button class="boss-tab" class:active={bossPanelTab === "ppr"} onclick={() => { bossPanelTab = "ppr"; showFireConfirm = false; loadOfficerPPR(); }}>
					<span class="material-icons boss-tab-icon">rate_review</span>
					PPR
				</button>
				<button class="boss-tab" class:active={bossPanelTab === "fto"} onclick={() => { bossPanelTab = "fto"; showFireConfirm = false; loadOfficerFTO(); }}>
					<span class="material-icons boss-tab-icon">school</span>
					FTO
				</button>
				<button class="boss-tab" class:active={bossPanelTab === "ia_history"} onclick={() => { bossPanelTab = "ia_history"; showFireConfirm = false; loadIAHistory(); }}>
					<span class="material-icons boss-tab-icon">shield</span>
					IA History
				</button>
				<button class="boss-tab" class:active={bossPanelTab === "activity"} onclick={() => { bossPanelTab = "activity"; showFireConfirm = false; }}>
					<span class="material-icons boss-tab-icon">history</span>
					Activity
				</button>
			</div>

			<div class="boss-body">
				{#if bossPanelTab === "rank" || bossPanelTab === "callsign" || bossPanelTab === "access" || bossPanelTab === "certs"}
					<div class="boss-section">
						<label class="boss-label">{bossPanelTab === "rank" ? "Step 1. Written Reason" : "Written Reason"}</label>
						<input class="callsign-input" bind:value={actionReason} maxlength="500" placeholder="Required reason for this personnel action" />
						{#if bossPanelTab === "rank"}
							<p class="boss-hint">A reason is required for the permanent personnel record.</p>
						{/if}
					</div>
				{/if}
				{#if bossPanelTab === "rank"}
					<div class="boss-section">
						<label class="boss-label">Step 2. Select New Rank</label>
						<p class="boss-hint">Current rank: <strong>{selectedOfficer.rank}</strong>. You may only select a rank below your own.</p>
						{#if isBossPanelLoading && jobGrades.length === 0}
							<div class="no-tags">
								<div class="loading-spinner"></div>
								<p>Loading agency ranks...</p>
							</div>
						{:else if jobGrades.length === 0}
							<div class="no-tags">
								<p>No ranks could be loaded for {selectedOfficer.departmentLabel || selectedOfficer.department || "this agency"}.</p>
							</div>
						{:else}
							<div class="grade-grid">
								{#each jobGrades as grade (grade.grade)}
									<button
										class="grade-option"
										class:selected={selectedGrade === grade.grade}
										class:current={grade.name === selectedOfficer.rank}
										class:is-boss={grade.isBoss}
										onclick={() => selectedGrade = grade.grade}
									>
										<span class="grade-number">{grade.grade}</span>
										<span class="grade-name">{grade.name}</span>
										{#if grade.name === selectedOfficer.rank}
											<span class="grade-current">Current</span>
										{/if}
										{#if grade.isBoss}
											<span class="grade-boss-badge">Head</span>
										{/if}
									</button>
								{/each}
							</div>
							<div class="grade-action-row" style="margin-top: 10px; display: flex; justify-content: flex-end;">
								<div style="flex: 1; align-self: center;">
									<p class="boss-hint" style="margin: 0;">{promotionAction.hint}</p>
								</div>
								<button class="btn-save" onclick={promoteOfficer} disabled={promotionAction.disabled}>
									{promotionAction.label}
								</button>
							</div>
						{/if}
					</div>

					<div class="boss-divider"></div>

					<div class="boss-section">
						<label class="boss-label">Agency Transfer</label>
						<p class="boss-hint">Transfer the officer to another agency at an approved receiving rank.</p>
						<div class="callsign-input-row">
							<select class="callsign-input" bind:value={transferAgency} onchange={() => loadTransferGrades(transferAgency)}>
								<option value="brpd">BRPD</option><option value="ebrso">EBRSO</option><option value="lsp">LSP</option>
							</select>
							<select class="callsign-input" bind:value={transferGrade}>
								<option value={null}>Select receiving rank</option>
								{#each transferGrades as grade (grade.grade)}<option value={grade.grade}>{grade.name}</option>{/each}
							</select>
							<button class="btn-save" onclick={transferOfficer} disabled={isSavingBoss || transferGrade === null || actionReason.trim().length < 3}>Transfer</button>
						</div>
					</div>

					<div class="boss-divider"></div>

					<div class="boss-section">
						<label class="boss-label boss-label-danger">{term.terminate}</label>
						<p class="boss-hint">{term.removeHint}</p>
						{#if !showFireConfirm}
							<button class="btn-fire" onclick={() => showFireConfirm = true}>
								<span class="material-icons">person_remove</span>
								{term.terminate}
							</button>
						{:else}
							<div class="fire-confirm">
								<p class="fire-warning">Are you sure you want to terminate <strong>{selectedOfficer.firstName} {selectedOfficer.lastName}</strong>?</p>
								{#if isEmsDomain}
									<label class="fire-delete-toggle">
										<input type="checkbox" bind:checked={deleteUserData} />
										<span>Delete all user data from MDT</span>
									</label>
									{#if deleteUserData}
										<p class="fire-delete-hint">Removes this person's logs, tags, status, FTO/PPR file, clock records and patrol membership. Reports, evidence, cases, warrants and arrests are kept.</p>
									{/if}
								{/if}
								<div class="fire-actions">
									<button class="btn-cancel" onclick={() => showFireConfirm = false}>Cancel</button>
									<button class="btn-fire-confirm" onclick={fireOfficer} disabled={isSavingBoss || actionReason.trim().length < 3}>
										{isSavingBoss ? "Processing..." : "Confirm Termination"}
									</button>
								</div>
							</div>
						{/if}
					</div>

				{:else if bossPanelTab === "callsign"}
					<div class="boss-section">
						<label class="boss-label">Edit Callsign</label>
						<p class="boss-hint">Update this {term.memberLower}'s persistent callsign and permanent badge number.</p>
						<div class="callsign-input-row">
							<input
								type="text"
								class="callsign-input"
								bind:value={editCallsign}
								placeholder="Enter callsign..."
								maxlength="16"
							/>
							<button class="btn-save" onclick={saveCallsign} disabled={isSavingBoss || editCallsign.trim().length === 0 || actionReason.trim().length < 3}>Save Callsign</button>
						</div>
						<label class="boss-label">Permanent Badge Number</label>
						<div class="callsign-input-row">
							<input type="text" class="callsign-input" bind:value={editBadge} maxlength="20" placeholder="Badge number" />
							<button class="btn-save" onclick={saveBadge} disabled={isSavingBoss || editBadge.trim().length === 0 || actionReason.trim().length < 3}>Save Badge</button>
						</div>
						<label class="boss-label">Assignment</label>
						<div class="callsign-input-row">
							<select class="callsign-input" bind:value={editAssignment}>
								<option value="academy">Academy</option>
								<option value="field_training">Field Training</option>
								<option value="patrol">Patrol</option>
								<option value="investigations">Investigations</option>
								<option value="traffic">Traffic</option>
								<option value="administration">Administration</option>
								<option value="internal_affairs">Internal Affairs</option>
								<option value="personnel">Personnel</option>
								<option value="recruitment">Recruitment</option>
								<option value="training">Training</option>
								<option value="dispatcher">Dispatcher</option>
								<option value="fleet_manager">Fleet Manager</option>
								<option value="incident_command">Incident Command</option>
								<option value="evidence">Evidence</option>
								<option value="field_training_officer">Field Training Officer</option>
								<option value="k9_unit">K9 Unit</option>
								<option value="tactical_unit">Tactical Unit (SWAT)</option>
								<option value="aviation_unit">Aviation Unit (Air)</option>
								<option value="interceptor_unit">Interceptor Unit</option>
								<option value="marine_unit">Marine Unit</option>
								<option value="public_information">Public Information</option>
								<option value="honor_guard">Honor Guard</option>
							</select>
							<label class="fire-delete-toggle"><input type="checkbox" bind:checked={assignmentPrimary} /><span>Primary</span></label>
							<label class="fire-delete-toggle"><input type="checkbox" bind:checked={assignmentActive} /><span>Active</span></label>
							<button class="btn-save" onclick={saveAssignment} disabled={isSavingBoss || actionReason.trim().length < 3}>{assignmentActive ? "Assign" : "Remove"}</button>
						</div>
						<label class="boss-label">Employment Status</label>
						<div class="callsign-input-row">
							<select class="callsign-input" bind:value={editStatus}>
								<option value="probationary">Probationary</option><option value="active">Active</option>
								<option value="leave">Leave</option><option value="suspended">Suspended</option>
							</select>
							<button class="btn-save" onclick={saveStatus} disabled={isSavingBoss || actionReason.trim().length < 3}>Update Status</button>
						</div>
					</div>

				{:else if bossPanelTab === "access"}
					<div class="boss-section">
						<label class="boss-label">Protected Compartment</label>
						<p class="boss-hint">Protected records require explicit compartment access. Rank alone never bypasses this control.</p>
						<div class="callsign-input-row">
							<select class="callsign-input" bind:value={editCompartment} onchange={() => compartmentActive = !officerHasCompartment(selectedOfficer, editCompartment)}>
								<option value="internal_affairs">Internal Affairs</option><option value="undercover">Undercover</option><option value="personnel">Protected Personnel</option>
							</select>
							<input class="callsign-input" type="datetime-local" bind:value={compartmentExpiresAt} />
							<label class="fire-delete-toggle"><input type="checkbox" bind:checked={compartmentActive} /><span>Active</span></label>
							<button class="btn-save" onclick={saveCompartment} disabled={isSavingBoss || actionReason.trim().length < 3}>{compartmentActive ? "Grant" : "Revoke"}</button>
						</div>
					</div>

					<div class="boss-divider"></div>

					<div class="boss-section">
						<label class="boss-label">Permission Override</label>
						<p class="boss-hint">Agency heads may issue expiring access or place an explicit restriction. Restrictions win over every rank and assignment permission.</p>
						<div class="callsign-input-row">
							<select class="callsign-input" bind:value={editPermission}>
								<option value="records.review">Review Records</option><option value="records.lifecycle">Manage Record Lifecycle</option>
								<option value="dispatch.assign_other">Assign Dispatch Units</option><option value="dispatch.major_incident">Manage Major Incidents</option>
								<option value="evidence.release">Release Evidence</option><option value="personnel.protected_view">View Protected Personnel</option>
								<option value="compartment.internal_affairs">Internal Affairs Records</option>
							</select>
							<input class="callsign-input" type="datetime-local" bind:value={permissionExpiresAt} />
							<button class="btn-save" onclick={grantTemporaryPermission} disabled={isSavingBoss || !permissionExpiresAt || actionReason.trim().length < 3}>Temporary Grant</button>
						</div>
						<div class="callsign-input-row">
							<input class="callsign-input" type="datetime-local" bind:value={restrictionExpiresAt} />
							<label class="fire-delete-toggle"><input type="checkbox" bind:checked={restrictionActive} /><span>Restricted</span></label>
							<button class="btn-save" onclick={saveRestriction} disabled={isSavingBoss || actionReason.trim().length < 3}>{restrictionActive ? "Restrict" : "Restore"}</button>
						</div>
					</div>

				{:else if bossPanelTab === "certs"}
					<div class="boss-section">
						<label class="boss-label">Manage Certifications</label>
						<input class="callsign-input" type="datetime-local" bind:value={certExpiresAt} />
						<p class="boss-hint">Expiration is optional. Supplying one renews every selected certification through that date.</p>
						{#if availableTags.length === 0}
							<div class="no-tags">
								<span class="material-icons no-tags-icon">label_off</span>
								<p>No certifications available.</p>
								<p class="no-tags-hint">Create {term.memberLower} tags in Management &gt; Tags</p>
							</div>
						{:else}
							<div class="cert-grid">
								{#each availableTags as tag (tag.id)}
									<button
										class="cert-option"
										class:selected={selectedCerts.includes(tag.name)}
										onclick={() => toggleCert(tag.name)}
										use:tip={tag.description}
										style="--tag-color: {tag.color}"
									>
										<span class="cert-check">
											{#if selectedCerts.includes(tag.name)}
												<span class="material-icons">check_circle</span>
											{:else}
												<span class="material-icons">radio_button_unchecked</span>
											{/if}
										</span>
										<span class="cert-color-dot" style="background: {tag.color}"></span>
										<span class="cert-label">{tag.name}</span>
									</button>
								{/each}
							</div>
						{/if}
					</div>

				{:else if bossPanelTab === "ppr"}
					<div class="boss-section">
						<label class="boss-label">Performance Reviews</label>
						<p class="boss-hint">Performance planning and review entries for this {term.memberLower}.</p>
						{#if pprHistoryLoading}
							<p class="boss-hint">Loading...</p>
						{:else if pprHistory.length === 0}
							<div class="no-tags">
								<span class="material-icons no-tags-icon">rate_review</span>
								<p>No PPR entries found for this {term.memberLower}.</p>
							</div>
						{:else}
							<div class="ia-history-list">
								{#each pprHistory as ppr}
									<div class="ia-history-item">
										<div class="ia-history-info">
											<span class="ia-history-number">{ppr.ppr_number}</span>
											<span class="ia-pill {getPPRCategoryClass(ppr.category)}">{formatPPRCategory(ppr.category)}</span>
										</div>
										<div class="ia-history-meta">
											<span style="flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">{ppr.title}</span>
											<span class="ia-history-date">{formatDateShort(ppr.created_at)}</span>
										</div>
										<div class="ia-history-meta">
											<span style="color: rgba(255,255,255,0.35); font-size: 9px;">By {ppr.author_name}</span>
										</div>
									</div>
								{/each}
							</div>
						{/if}
					</div>

				{:else if bossPanelTab === "fto"}
					<div class="boss-section">
						<label class="boss-label">Field Training History</label>
						<p class="boss-hint">FTO training assignments for this {term.memberLower}.</p>
						{#if ftoHistoryLoading}
							<p class="boss-hint">Loading...</p>
						{:else if ftoHistory.length === 0}
							<div class="no-tags">
								<span class="material-icons no-tags-icon">school</span>
								<p>No FTO records found for this {term.memberLower}.</p>
							</div>
						{:else}
							<div class="ia-history-list">
								{#each ftoHistory as record}
									<div class="ia-history-item">
										<div class="ia-history-info">
											<span class="ia-history-number">{record.fto_number}</span>
											<span class="ia-pill {getFTOStatusClass(record.status)}">{record.status.toUpperCase()}</span>
										</div>
										<div class="ia-history-meta">
											<span style="flex:1;">
												{record.trainee_name === `${selectedOfficer?.firstName || ''} ${selectedOfficer?.lastName || ''}`.trim() ? 'Trainer' : 'Trainee'}:
												{record.trainee_name === `${selectedOfficer?.firstName || ''} ${selectedOfficer?.lastName || ''}`.trim() ? record.trainer_name : record.trainee_name}
											</span>
											{#if record.phase_name}
												<span style="color: rgba(255,255,255,0.5); font-size: 9px;">{record.phase_name}</span>
											{/if}
										</div>
										<div class="ia-history-meta">
											{#if record.dor_count}
												<span style="color: rgba(255,255,255,0.35); font-size: 9px;">{record.dor_count} DOR{record.dor_count !== 1 ? 's' : ''}</span>
											{/if}
											{#if record.latest_rating}
												<span style="color: rgba(255,255,255,0.5); font-size: 9px;">Rating: {record.latest_rating}/5</span>
											{/if}
											<span class="ia-history-date">{formatDateShort(record.start_date || record.created_at)}</span>
										</div>
									</div>
								{/each}
							</div>
						{/if}
					</div>

				{:else if bossPanelTab === "ia_history"}
					<div class="boss-section">
						<label class="boss-label">IA Complaint History</label>
						<p class="boss-hint">Internal affairs complaints involving this {term.memberLower}.</p>
						{#if iaHistoryLoading}
							<p class="boss-hint">Loading...</p>
						{:else if iaHistory.length === 0}
							<div class="no-tags">
								<span class="material-icons no-tags-icon">verified_user</span>
								<p>No IA complaints found for this {term.memberLower}.</p>
							</div>
						{:else}
							<div class="ia-history-list">
								{#each iaHistory as complaint}
									<div class="ia-history-item">
										<div class="ia-history-info">
											<span class="ia-history-number">{complaint.complaint_number}</span>
											<span class="ia-pill {getIAStatusClass(complaint.status)}">{formatIAStatus(complaint.status)}</span>
										</div>
										<div class="ia-history-meta">
											<span>{formatIAStatus(complaint.category)}</span>
											<span class="ia-history-date">{complaint.created_at ? formatDate(complaint.created_at) : '-'}</span>
										</div>
									</div>
								{/each}
							</div>
						{/if}
					</div>

				{:else if bossPanelTab === "activity"}
					<div class="boss-section">
						<label class="boss-label">Activity Timeline</label>
						<p class="boss-hint">Recorded changes involving this {term.memberLower}, including rank, callsign, status and more.</p>
						{#if selectedOfficer?.citizenid}
							<ActivityTimeline citizenid={selectedOfficer.citizenid} />
						{/if}
					</div>
				{/if}
			</div>

			<div class="modal-footer">
				<button class="btn-cancel" onclick={closeBossPanel}>Close</button>
				{#if bossPanelTab === "certs"}
					<button
						class="btn-save"
						onclick={saveCertifications}
						disabled={isSavingCerts || availableTags.length === 0 || actionReason.trim().length < 3}
					>
						{isSavingCerts ? "Saving..." : "Save Certifications"}
					</button>
				{/if}
			</div>
		</div>
	</div>
{/if}

{#if showHireModal}
	<div class="modal-overlay" onclick={() => showHireModal = false} role="presentation">
		<div class="modal-container" onclick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-label="Hire officer">
			<div class="modal-header">
				<div class="modal-title-area"><span class="modal-title">Hire Officer</span><span class="modal-subtitle">Entry rank and academy assignment are applied automatically.</span></div>
				<button class="modal-close" onclick={() => showHireModal = false}><span class="material-icons">close</span></button>
			</div>
			<div class="modal-body boss-section">
				<label class="boss-label">Citizen ID</label><input class="callsign-input" bind:value={hireCitizenId} placeholder="Citizen ID" />
				<label class="boss-label">Permanent Badge Number</label><input class="callsign-input" bind:value={hireBadge} maxlength="20" placeholder="Badge number" />
				<label class="boss-label">Initial Callsign</label><input class="callsign-input" bind:value={hireCallsign} maxlength="32" placeholder="Callsign" />
				<label class="boss-label">Written Reason</label><input class="callsign-input" bind:value={hireReason} maxlength="500" placeholder="Hiring reason" />
			</div>
			<div class="modal-footer">
				<button class="btn-cancel" onclick={() => showHireModal = false}>Cancel</button>
				<button class="btn-save" onclick={hireOfficer} disabled={isSavingBoss || [hireCitizenId, hireBadge, hireCallsign, hireReason].some((value) => value.trim().length < 3)}>{isSavingBoss ? "Hiring..." : "Hire Officer"}</button>
			</div>
		</div>
	</div>
{/if}

{#if showTaskForceModal}
	<div class="modal-overlay" onclick={() => showTaskForceModal = false} role="presentation">
		<div class="modal-container taskforce-modal" onclick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-label="Task Force Management">
			<div class="modal-header">
				<div class="modal-title-area">
					<span class="modal-title">Task Force Management</span>
					<span class="modal-subtitle">Time-limited, written cross-agency authority for BRPD, EBRSO and LSP.</span>
				</div>
				<div class="taskforce-header-actions">
					<button class="btn-secondary" onclick={loadTaskForces} disabled={taskForceLoading}>{taskForceLoading ? "Loading..." : "Refresh"}</button>
					{#if canManageTaskForces}<button class="btn-save" onclick={() => { taskForceCreating = true; selectedTaskForceId = ""; }}>New Task Force</button>{/if}
					<button class="modal-close" onclick={() => showTaskForceModal = false} aria-label="Close"><span class="material-icons">close</span></button>
				</div>
			</div>

			<div class="modal-body taskforce-layout">
				<div class="taskforce-list">
					{#if taskForces.length === 0}
						<div class="no-tags"><span class="material-icons no-tags-icon">groups</span><p>No task forces are visible.</p></div>
					{:else}
						{#each taskForces as taskForce (taskForce.id)}
							<button class="taskforce-card" class:selected={taskForce.id === selectedTaskForceId} onclick={() => { selectedTaskForceId = taskForce.id; taskForceCreating = false; }}>
								<span class="taskforce-card-name">{taskForce.name}</span>
								<span class="taskforce-card-meta">{taskForce.appointingAgency.toUpperCase()}, {taskForce.status}</span>
								<span class="taskforce-card-meta">Expires {formatDate(taskForce.expiresAt || "", "")}</span>
							</button>
						{/each}
					{/if}
				</div>

				<div class="taskforce-detail">
					{#if taskForceCreating}
						<div class="taskforce-section">
							<h3>Create Task Force</h3>
							<label class="boss-label" for="taskforce-name">Name</label>
							<input id="taskforce-name" class="callsign-input" bind:value={taskForceName} maxlength="100" placeholder="Task force name" />
							<label class="boss-label" for="taskforce-expiry">Expiration</label>
							<input id="taskforce-expiry" class="callsign-input" type="datetime-local" bind:value={taskForceExpiresAt} />
							<label class="boss-label" for="taskforce-reason">Written Reason</label>
							<textarea id="taskforce-reason" class="callsign-input taskforce-textarea" bind:value={taskForceReason} maxlength="500" placeholder="Operational purpose and approving authority"></textarea>
						</div>

						<div class="taskforce-section">
							<h3>Participating Agencies</h3>
							<div class="taskforce-options">
								{#each [["brpd", "BRPD"], ["ebrso", "EBRSO"], ["lsp", "LSP"]] as agency}
									<label class="fire-delete-toggle"><input type="checkbox" checked={taskForceAgencies.includes(agency[0])} onchange={() => taskForceAgencies = toggleTaskForceValue(taskForceAgencies, agency[0])} /><span>{agency[1]}</span></label>
								{/each}
							</div>
							<p class="boss-hint">At least two agencies are required.</p>
						</div>

						<div class="taskforce-section">
							<h3>Authorized Actions</h3>
							<div class="taskforce-options taskforce-permissions">
								{#each taskForcePermissionOptions as permission}
									<label class="fire-delete-toggle"><input type="checkbox" checked={taskForcePermissions.includes(permission)} onchange={() => taskForcePermissions = toggleTaskForceValue(taskForcePermissions, permission)} /><span>{permission}</span></label>
								{/each}
							</div>
						</div>

						<div class="taskforce-section">
							<h3>Record Scope</h3>
							<div class="taskforce-options">
								{#each ["cases", "reports", "incidents"] as recordType}
									<label class="fire-delete-toggle"><input type="checkbox" checked={taskForceRecordTypes.includes(recordType)} onchange={() => taskForceRecordTypes = toggleTaskForceValue(taskForceRecordTypes, recordType)} /><span>{recordType}</span></label>
								{/each}
							</div>
							<div class="taskforce-id-grid">
								<input class="callsign-input" bind:value={taskForceCaseIds} placeholder="Specific case IDs, comma separated" />
								<input class="callsign-input" bind:value={taskForceReportIds} placeholder="Specific report IDs, comma separated" />
								<input class="callsign-input" bind:value={taskForceIncidentIds} placeholder="Specific incident IDs, comma separated" />
							</div>
						</div>

						<div class="taskforce-actions">
							<button class="btn-cancel" onclick={() => taskForceCreating = false}>Cancel</button>
							<button class="btn-save" onclick={createTaskForce} disabled={taskForceSaving || taskForceName.trim().length < 3 || taskForceReason.trim().length < 3 || !taskForceExpiresAt || taskForceAgencies.length < 2 || taskForcePermissions.length === 0}>{taskForceSaving ? "Creating..." : "Create Task Force"}</button>
						</div>
					{:else if selectedTaskForce}
						<div class="taskforce-summary">
							<div><h3>{selectedTaskForce.name}</h3><p>{selectedTaskForce.reason}</p></div>
							<span class="status-pill {selectedTaskForce.status === 'active' ? 'on-duty' : 'off-duty'}">{selectedTaskForce.status}</span>
						</div>
						<div class="taskforce-scope-summary">
							<span><strong>Agencies:</strong> {(selectedTaskForce.scope.agencies || []).map((agency) => agency.toUpperCase()).join(", ")}</span>
							<span><strong>Expires:</strong> {formatDate(selectedTaskForce.expiresAt || "", "")}</span>
							<span><strong>Records:</strong> {(selectedTaskForce.scope.recordTypes || []).join(", ") || "Specific records only"}</span>
							<span><strong>Permissions:</strong> {(selectedTaskForce.scope.permissions || []).join(", ")}</span>
						</div>

						<div class="taskforce-section">
							<h3>Members</h3>
							<div class="taskforce-members">
								{#each selectedTaskForce.members || [] as member (member.citizenid + member.startsAt)}
									<div class="taskforce-member"><span>{member.callsign}, {member.citizenid}</span><span>{member.agency.toUpperCase()}, {member.role}, {member.status}</span></div>
								{/each}
							</div>
						</div>

						{#if canManageTaskForces}
							<div class="taskforce-section">
								<h3>Appoint or Change Member</h3>
								<div class="taskforce-form-grid">
									<select class="callsign-input" bind:value={taskForceMemberCitizenId}>
										<option value="">Select officer</option>
										{#each officers.filter((officer) => officer.citizenid && (selectedTaskForce?.scope.agencies || []).includes(officer.department || "")) as officer (officer.citizenid)}
											<option value={officer.citizenid}>{officer.callsign}, {officer.firstName} {officer.lastName}, {(officer.department || "").toUpperCase()}</option>
										{/each}
									</select>
									<select class="callsign-input" bind:value={taskForceMemberRole}><option value="commander">Commander</option><option value="supervisor">Supervisor</option><option value="member">Member</option><option value="analyst">Analyst</option></select>
									<select class="callsign-input" bind:value={taskForceMemberStatus}><option value="active">Active</option><option value="suspended">Suspended</option><option value="revoked">Revoke</option></select>
									<input class="callsign-input" type="datetime-local" bind:value={taskForceMemberExpiresAt} disabled={taskForceMemberStatus === "revoked"} />
								</div>
								<label class="boss-label" for="taskforce-member-reason">Written Reason</label>
								<input id="taskforce-member-reason" class="callsign-input" bind:value={taskForceMemberReason} maxlength="500" placeholder="Appointment, suspension or removal reason" />
								<button class="btn-save" onclick={saveTaskForceMember} disabled={taskForceSaving || !taskForceMemberCitizenId || taskForceMemberReason.trim().length < 3 || ((taskForceMemberStatus === "active" || taskForceMemberStatus === "suspended") && !taskForceMemberExpiresAt)}>Save Membership</button>
							</div>

							<div class="taskforce-section">
								<h3>Task Force Status</h3>
								<div class="taskforce-form-grid status-grid">
									<select class="callsign-input" bind:value={taskForceStatus}><option value="active">Active</option><option value="suspended">Suspended</option><option value="closed">Closed</option><option value="expired">Expired</option></select>
									<input class="callsign-input" bind:value={taskForceStatusReason} maxlength="500" placeholder="Written Reason" />
									<button class="btn-save" onclick={saveTaskForceStatus} disabled={taskForceSaving || taskForceStatusReason.trim().length < 3}>Update Status</button>
								</div>
							</div>
						{/if}
					{:else}
						<div class="no-tags"><span class="material-icons no-tags-icon">policy</span><p>Select a task force to review its scope and membership.</p></div>
					{/if}
				</div>
			</div>
		</div>
	</div>
{/if}

<style>
	.roster-page {
		display: flex;
		flex-direction: column;
		height: 100%;
		background: var(--card-dark-bg);
		color: rgba(255, 255, 255, 0.9);
		overflow: hidden;
	}

	.topbar {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 0 16px;
		height: 42px;
		flex-shrink: 0;
		border-bottom: 1px solid rgba(255, 255, 255, 0.06);
	}

	.search-input {
		flex: 1;
		max-width: 360px;
		background: transparent;
		border: none;
		padding: 0;
		color: rgba(255, 255, 255, 0.8);
		font-size: 12px;
	}

	.search-input:focus {
		outline: none;
	}

	.search-input::placeholder {
		color: rgba(255, 255, 255, 0.2);
	}

	.topbar-right {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-left: auto;
	}

	.result-count {
		color: rgba(255, 255, 255, 0.2);
		font-size: 10px;
	}

	.btn-secondary {
		background: transparent;
		border: 1px solid rgba(255, 255, 255, 0.06);
		border-radius: 3px;
		padding: 4px 10px;
		color: rgba(255, 255, 255, 0.4);
		font-size: 10px;
		font-weight: 500;
		cursor: pointer;
		transition: all 0.1s;
	}

	.btn-secondary:hover:not(:disabled) {
		color: rgba(255, 255, 255, 0.7);
		border-color: rgba(255, 255, 255, 0.1);
	}

	.btn-secondary:disabled {
		opacity: 0.3;
		cursor: not-allowed;
	}

	.content-area {
		display: grid;
		grid-template-columns: 1fr 180px;
		gap: 0;
		flex: 1;
		min-height: 0;
		overflow: hidden;
	}

	.list-panel {
		background: transparent;
		border: none;
		border-radius: 0;
		display: flex;
		flex-direction: column;
		overflow: hidden;
		border-right: 1px solid rgba(255, 255, 255, 0.06);
	}

	.table-header {
		display: grid;
		grid-template-columns: 80px 70px 1.2fr 70px 1fr 0.8fr 1.5fr;
		gap: 8px;
		padding: 8px 16px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.06);
	}

	.col-header {
		font-size: 9px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.6px;
		color: rgba(255, 255, 255, 0.35);
		background: none;
		border: none;
		padding: 0;
		text-align: left;
		cursor: default;
	}

	.col-header.sortable {
		cursor: pointer;
	}

	.col-header.sortable:hover {
		color: rgba(255, 255, 255, 0.5);
	}

	.table-body {
		flex: 1;
		overflow-y: auto;
	}

	.table-row {
		display: grid;
		grid-template-columns: 80px 70px 1.2fr 70px 1fr 0.8fr 1.5fr;
		gap: 8px;
		padding: 7px 16px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.03);
		font-size: 11px;
		align-items: center;
		transition: background 0.1s;
	}

	.table-row:hover {
		background: rgba(255, 255, 255, 0.02);
	}

	.table-row.clickable {
		cursor: pointer;
	}

	.table-row.clickable:hover {
		background: rgba(255, 255, 255, 0.03);
	}

	.table-row:last-child {
		border-bottom: none;
	}

	.cell-callsign {
		font-family: monospace;
		font-size: 10px;
		color: rgba(var(--accent-text-rgb), 0.7);
		font-weight: 500;
	}

	.cell-name {
		font-weight: 500;
		font-size: 11px;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.cell-rank {
		color: rgba(255, 255, 255, 0.35);
		font-size: 10px;
	}

	.cell-dept {
		color: rgba(255, 255, 255, 0.35);
		font-size: 10px;
	}

	.cell-radio {
		font-size: 10px;
	}

	.radio-badge {
		display: inline-block;
		padding: 1px 6px;
		border-radius: 3px;
		font-size: 9px;
		font-weight: 600;
		font-family: monospace;
		background: rgba(var(--accent-rgb), 0.08);
		color: rgba(var(--accent-text-rgb), 0.7);
		border: 1px solid rgba(var(--accent-rgb), 0.1);
	}

	.cell-muted {
		color: rgba(255, 255, 255, 0.1);
	}

	.status-pill {
		display: inline-block;
		padding: 1px 6px;
		border-radius: 3px;
		font-size: 9px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.status-pill.on-duty {
		background: rgba(16, 185, 129, 0.08);
		color: rgba(110, 231, 183, 0.8);
		border: 1px solid rgba(16, 185, 129, 0.1);
	}

	.status-pill.off-duty {
		background: rgba(255, 255, 255, 0.03);
		color: rgba(255, 255, 255, 0.3);
		border: 1px solid rgba(255, 255, 255, 0.05);
	}

	.cell-certs {
		display: flex;
		flex-wrap: wrap;
		gap: 3px;
	}

	.cert-tag {
		padding: 1px 5px;
		background: rgba(255, 255, 255, 0.03);
		border: 1px solid rgba(255, 255, 255, 0.05);
		border-radius: 3px;
		font-size: 9px;
	}

	/* Active Units Sidebar */
	.units-panel {
		background: transparent;
		border: none;
		border-radius: 0;
		display: flex;
		flex-direction: column;
		overflow: hidden;
	}

	.units-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 8px 14px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.06);
	}

	.units-label {
		font-size: 9px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.6px;
		color: rgba(255, 255, 255, 0.35);
	}

	.units-count {
		font-size: 10px;
		font-weight: 600;
		color: rgba(255, 255, 255, 0.35);
		background: rgba(255, 255, 255, 0.03);
		padding: 1px 6px;
		border-radius: 3px;
	}

	.units-list {
		flex: 1;
		overflow-y: auto;
	}

	.unit-row {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 14px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.03);
		font-size: 11px;
	}

	.unit-row:last-child {
		border-bottom: none;
	}

	.unit-callsign {
		font-family: monospace;
		font-size: 10px;
		color: rgba(var(--accent-text-rgb), 0.7);
		font-weight: 500;
		min-width: 28px;
	}

	.unit-name {
		color: rgba(255, 255, 255, 0.5);
		font-size: 11px;
	}

	.units-empty {
		display: flex;
		align-items: center;
		justify-content: center;
		height: 80px;
		color: rgba(255, 255, 255, 0.35);
		font-size: 10px;
	}

	/* States */
	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 200px;
		text-align: center;
		color: rgba(255, 255, 255, 0.35);
	}

	.empty-title {
		font-size: 14px;
		font-weight: 600;
		color: rgba(255, 255, 255, 0.4);
		margin: 0 0 4px;
	}

	.empty-sub {
		font-size: 11px;
		color: rgba(255, 255, 255, 0.35);
		margin: 0;
	}

	.loading-spinner {
		width: 24px;
		height: 24px;
		border: 2px solid rgba(255, 255, 255, 0.06);
		border-left: 2px solid rgba(var(--accent-rgb), 0.5);
		border-radius: 50%;
		animation: spin 0.8s linear infinite;
		margin-bottom: 10px;
	}

	@keyframes spin {
		0% { transform: rotate(0deg); }
		100% { transform: rotate(360deg); }
	}

	/* Scrollbars */
	.table-body::-webkit-scrollbar,
	.units-list::-webkit-scrollbar {
		width: 4px;
	}

	.table-body::-webkit-scrollbar-track,
	.units-list::-webkit-scrollbar-track {
		background: transparent;
	}

	.table-body::-webkit-scrollbar-thumb,
	.units-list::-webkit-scrollbar-thumb {
		background: rgba(255, 255, 255, 0.06);
		border-radius: 2px;
	}

	/* Certification Modal */
	.modal-overlay {
		position: fixed;
		top: 0;
		left: 0;
		width: 100%;
		height: 100%;
		background: rgba(0, 0, 0, 0.6);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 1000;
	}

	.modal-container {
		background: var(--card-dark-bg);
		border: 1px solid rgba(255, 255, 255, 0.08);
		border-radius: 6px;
		width: 400px;
		max-height: 80vh;
		display: flex;
		flex-direction: column;
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
	}

	.taskforce-modal { width: min(980px, 92vw); max-height: 88vh; }
	.taskforce-header-actions { display: flex; align-items: center; gap: 8px; }
	.taskforce-layout { display: grid; grid-template-columns: 240px 1fr; padding: 0; min-height: 620px; }
	.taskforce-list { border-right: 1px solid rgba(255, 255, 255, 0.06); overflow-y: auto; padding: 8px; }
	.taskforce-card { width: 100%; display: flex; flex-direction: column; gap: 3px; text-align: left; background: transparent; color: inherit; border: 1px solid transparent; border-radius: 5px; padding: 10px; cursor: pointer; margin-bottom: 6px; }
	.taskforce-card:hover, .taskforce-card.selected { background: rgba(var(--accent-rgb), 0.08); border-color: rgba(var(--accent-rgb), 0.18); }
	.taskforce-card-name { font-size: 11px; font-weight: 650; }
	.taskforce-card-meta { font-size: 9px; color: rgba(255, 255, 255, 0.35); text-transform: uppercase; letter-spacing: 0.35px; }
	.taskforce-detail { overflow-y: auto; padding: 16px; }
	.taskforce-section { display: flex; flex-direction: column; gap: 8px; padding: 0 0 16px; margin-bottom: 16px; border-bottom: 1px solid rgba(255, 255, 255, 0.06); }
	.taskforce-section h3, .taskforce-summary h3 { margin: 0; font-size: 12px; color: rgba(255, 255, 255, 0.82); }
	.taskforce-textarea { min-height: 68px; resize: vertical; }
	.taskforce-options { display: flex; gap: 12px; flex-wrap: wrap; }
	.taskforce-permissions { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 7px 12px; }
	.taskforce-id-grid, .taskforce-form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
	.taskforce-actions { display: flex; justify-content: flex-end; gap: 8px; }
	.taskforce-summary { display: flex; justify-content: space-between; gap: 16px; align-items: flex-start; margin-bottom: 12px; }
	.taskforce-summary p { margin: 4px 0 0; font-size: 10px; color: rgba(255, 255, 255, 0.4); }
	.taskforce-scope-summary { display: grid; gap: 6px; background: rgba(255, 255, 255, 0.025); border: 1px solid rgba(255, 255, 255, 0.05); border-radius: 5px; padding: 10px; margin-bottom: 16px; font-size: 10px; color: rgba(255, 255, 255, 0.48); overflow-wrap: anywhere; }
	.taskforce-members { display: grid; gap: 5px; max-height: 150px; overflow-y: auto; }
	.taskforce-member { display: flex; justify-content: space-between; gap: 12px; padding: 7px 9px; background: rgba(255, 255, 255, 0.025); border-radius: 4px; font-size: 10px; color: rgba(255, 255, 255, 0.55); }
	.status-grid { grid-template-columns: 160px 1fr auto; }

	.modal-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 12px 16px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.06);
	}

	.modal-title-area {
		display: flex;
		flex-direction: column;
		gap: 1px;
	}

	.modal-title {
		font-size: 12px;
		font-weight: 600;
		color: rgba(255, 255, 255, 0.85);
	}

	.modal-subtitle {
		font-size: 10px;
		color: rgba(255, 255, 255, 0.3);
	}

	.modal-close {
		background: none;
		border: none;
		color: rgba(255, 255, 255, 0.3);
		cursor: pointer;
		padding: 4px;
		border-radius: 3px;
		transition: all 0.1s;
		display: flex;
		align-items: center;
	}

	.modal-close:hover {
		color: rgba(255, 255, 255, 0.7);
		background: rgba(255, 255, 255, 0.04);
	}

	.modal-close .material-icons {
		font-size: 16px;
	}

	.modal-body {
		padding: 12px 16px;
		overflow-y: auto;
		flex: 1;
	}

	.no-tags {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: 24px 0;
		color: rgba(255, 255, 255, 0.3);
		text-align: center;
	}

	.no-tags-icon {
		font-size: 28px;
		margin-bottom: 8px;
		color: rgba(255, 255, 255, 0.1);
	}

	.no-tags p {
		margin: 0;
		font-size: 11px;
	}

	.no-tags-hint {
		font-size: 10px !important;
		color: rgba(255, 255, 255, 0.2) !important;
		margin-top: 4px !important;
	}

	.cert-grid {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.cert-option {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 7px 10px;
		background: transparent;
		border: 1px solid rgba(255, 255, 255, 0.05);
		border-radius: 3px;
		cursor: pointer;
		transition: all 0.1s;
		color: rgba(255, 255, 255, 0.6);
		font-size: 11px;
	}

	.cert-option:hover {
		background: rgba(255, 255, 255, 0.03);
		border-color: rgba(255, 255, 255, 0.08);
	}

	.cert-option.selected {
		background: color-mix(in srgb, var(--tag-color) 6%, transparent);
		border-color: color-mix(in srgb, var(--tag-color) 20%, transparent);
		color: rgba(255, 255, 255, 0.85);
	}

	.cert-check {
		display: flex;
		align-items: center;
		flex-shrink: 0;
	}

	.cert-check .material-icons {
		font-size: 16px;
		color: rgba(255, 255, 255, 0.15);
	}

	.cert-option.selected .cert-check .material-icons {
		color: var(--tag-color);
	}

	.cert-color-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.cert-label {
		font-weight: 500;
	}

	.modal-footer {
		display: flex;
		justify-content: flex-end;
		gap: 6px;
		padding: 10px 16px;
		border-top: 1px solid rgba(255, 255, 255, 0.06);
	}

	.btn-cancel {
		background: transparent;
		border: 1px solid rgba(255, 255, 255, 0.06);
		border-radius: 3px;
		padding: 4px 12px;
		color: rgba(255, 255, 255, 0.4);
		font-size: 10px;
		font-weight: 500;
		cursor: pointer;
		transition: all 0.1s;
	}

	.btn-cancel:hover {
		color: rgba(255, 255, 255, 0.7);
		border-color: rgba(255, 255, 255, 0.1);
	}

	.btn-save {
		background: rgba(var(--accent-rgb), 0.06);
		border: 1px solid rgba(var(--accent-rgb), 0.1);
		border-radius: 3px;
		padding: 5px 16px;
		color: rgba(var(--accent-text-rgb), 0.7);
		font-size: 10px;
		font-weight: 600;
		cursor: pointer;
		transition: all 0.1s;
	}

	.btn-save:hover:not(:disabled) {
		background: rgba(var(--accent-rgb), 0.12);
		color: rgba(var(--accent-text-rgb), 0.9);
	}

	.btn-save:disabled {
		opacity: 0.3;
		cursor: not-allowed;
	}

	/* Boss Panel */
	.boss-panel {
		background: var(--card-dark-bg);
		border: 1px solid rgba(255, 255, 255, 0.08);
		border-radius: 6px;
		width: 660px;
		max-width: 94vw;
		max-height: 85vh;
		display: flex;
		flex-direction: column;
		box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
	}

	.boss-tabs {
		display: flex;
		flex-wrap: wrap;
		gap: 0;
		border-bottom: 1px solid rgba(255, 255, 255, 0.06);
		padding: 0 16px;
	}

	.boss-tab {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 8px 10px;
		background: none;
		border: none;
		border-bottom: 2px solid transparent;
		color: rgba(255, 255, 255, 0.35);
		font-size: 10px;
		font-weight: 600;
		cursor: pointer;
		transition: all 0.15s;
		text-transform: uppercase;
		letter-spacing: 0.3px;
		white-space: nowrap;
	}

	.boss-tab:hover {
		color: rgba(255, 255, 255, 0.6);
	}

	.boss-tab.active {
		color: rgba(var(--accent-text-rgb), 0.85);
		border-bottom-color: rgba(var(--accent-rgb), 0.5);
	}

	.boss-tab-icon {
		font-size: 14px;
	}

	.boss-body {
		padding: 14px 16px;
		overflow-y: auto;
		flex: 1;
	}

	.boss-section {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.boss-label {
		font-size: 11px;
		font-weight: 600;
		color: rgba(255, 255, 255, 0.7);
	}

	.boss-label-danger {
		color: rgba(239, 68, 68, 0.8);
	}

	.boss-hint {
		font-size: 10px;
		color: rgba(255, 255, 255, 0.25);
		margin: 0 0 6px;
		line-height: 1.4;
	}

	.boss-divider {
		height: 1px;
		background: rgba(255, 255, 255, 0.06);
		margin: 14px 0;
	}

	/* Grade Grid */
	.grade-grid {
		display: flex;
		flex-direction: column;
		gap: 3px;
	}

	.grade-option {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 7px 10px;
		background: transparent;
		border: 1px solid rgba(255, 255, 255, 0.05);
		border-radius: 3px;
		cursor: pointer;
		transition: all 0.1s;
		color: rgba(255, 255, 255, 0.6);
		font-size: 11px;
		text-align: left;
	}

	.grade-option:hover {
		background: rgba(255, 255, 255, 0.03);
		border-color: rgba(255, 255, 255, 0.08);
	}

	.grade-option.selected {
		background: rgba(var(--accent-rgb), 0.08);
		border-color: rgba(var(--accent-rgb), 0.2);
		color: rgba(var(--accent-text-rgb), 0.9);
	}

	.grade-option.current {
		border-color: rgba(16, 185, 129, 0.15);
	}

	.grade-number {
		font-family: monospace;
		font-size: 9px;
		color: rgba(255, 255, 255, 0.2);
		min-width: 16px;
		text-align: center;
	}

	.grade-option.selected .grade-number {
		color: rgba(var(--accent-text-rgb), 0.5);
	}

	.grade-name {
		font-weight: 500;
		flex: 1;
	}

	.grade-current {
		font-size: 8px;
		text-transform: uppercase;
		letter-spacing: 0.5px;
		color: rgba(16, 185, 129, 0.7);
		font-weight: 600;
	}

	.grade-boss-badge {
		font-size: 8px;
		text-transform: uppercase;
		letter-spacing: 0.5px;
		color: rgba(251, 191, 36, 0.7);
		font-weight: 600;
		background: rgba(251, 191, 36, 0.08);
		padding: 1px 5px;
		border-radius: 2px;
	}

	/* Callsign Input */
	.callsign-input-row {
		display: flex;
		gap: 8px;
	}

	.callsign-input {
		flex: 1;
		background: rgba(255, 255, 255, 0.03);
		border: 1px solid rgba(255, 255, 255, 0.08);
		border-radius: 3px;
		padding: 7px 10px;
		color: rgba(255, 255, 255, 0.85);
		font-size: 12px;
		font-family: monospace;
	}

	.callsign-input:focus {
		outline: none;
		border-color: rgba(var(--accent-rgb), 0.3);
	}

	.callsign-input::placeholder {
		color: rgba(255, 255, 255, 0.15);
	}

	/* Fire Button */
	.btn-fire {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 6px 14px;
		background: rgba(239, 68, 68, 0.06);
		border: 1px solid rgba(239, 68, 68, 0.12);
		border-radius: 3px;
		color: rgba(239, 68, 68, 0.7);
		font-size: 10px;
		font-weight: 600;
		cursor: pointer;
		transition: all 0.15s;
		width: fit-content;
	}

	.btn-fire .material-icons {
		font-size: 14px;
	}

	.btn-fire:hover {
		background: rgba(239, 68, 68, 0.12);
		color: rgba(239, 68, 68, 0.9);
		border-color: rgba(239, 68, 68, 0.2);
	}

	.fire-confirm {
		background: rgba(239, 68, 68, 0.04);
		border: 1px solid rgba(239, 68, 68, 0.1);
		border-radius: 4px;
		padding: 10px 12px;
	}

	.fire-warning {
		font-size: 11px;
		color: rgba(255, 255, 255, 0.6);
		margin: 0 0 10px;
		line-height: 1.4;
	}

	.fire-warning strong {
		color: rgba(255, 255, 255, 0.85);
	}

	.fire-delete-toggle {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 12px;
		color: rgba(255, 255, 255, 0.85);
		cursor: pointer;
		margin: 0 0 8px;
		user-select: none;
	}

	.fire-delete-toggle input {
		accent-color: #ef4444;
		cursor: pointer;
	}

	.fire-delete-hint {
		font-size: 10px;
		color: rgba(255, 255, 255, 0.5);
		margin: 0 0 10px;
		line-height: 1.4;
	}

	.fire-actions {
		display: flex;
		gap: 6px;
		justify-content: flex-end;
	}

	.btn-fire-confirm {
		background: rgba(239, 68, 68, 0.15);
		border: 1px solid rgba(239, 68, 68, 0.25);
		border-radius: 3px;
		padding: 4px 12px;
		color: rgba(239, 68, 68, 0.9);
		font-size: 10px;
		font-weight: 600;
		cursor: pointer;
		transition: all 0.1s;
	}

	.btn-fire-confirm:hover:not(:disabled) {
		background: rgba(239, 68, 68, 0.25);
	}

	.btn-fire-confirm:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.ia-history-list {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.ia-history-item {
		background: rgba(255, 255, 255, 0.03);
		border: 1px solid rgba(255, 255, 255, 0.06);
		border-radius: 6px;
		padding: 8px 10px;
	}
	.ia-history-info {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-bottom: 3px;
	}
	.ia-history-number {
		font-size: 11px;
		font-weight: 600;
		color: rgba(255, 255, 255, 0.87);
	}
	.ia-history-meta {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 10px;
		color: rgba(255, 255, 255, 0.4);
	}
	.ia-history-date {
		margin-left: auto;
	}
	.ia-pill {
		font-size: 9px;
		padding: 1px 6px;
		border-radius: 3px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}
	.pill-blue { background: rgba(59, 130, 246, 0.2); color: rgb(147, 197, 253); }
	.pill-orange { background: rgba(245, 158, 11, 0.2); color: rgb(253, 224, 71); }
	.pill-yellow { background: rgba(234, 179, 8, 0.2); color: rgb(253, 224, 71); }
	.pill-red { background: rgba(239, 68, 68, 0.2); color: rgb(252, 165, 165); }
	.pill-green { background: rgba(16, 185, 129, 0.2); color: rgb(167, 243, 208); }
	.pill-gray { background: rgba(107, 114, 128, 0.2); color: rgb(156, 163, 175); }
	.status-active { background: rgba(59, 130, 246, 0.2); color: rgb(147, 197, 253); }
	.status-completed { background: rgba(16, 185, 129, 0.2); color: rgb(167, 243, 208); }
	.status-failed { background: rgba(239, 68, 68, 0.2); color: rgb(252, 165, 165); }
	.status-suspended { background: rgba(245, 158, 11, 0.2); color: rgb(253, 224, 71); }


</style>
