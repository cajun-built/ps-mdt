<script lang="ts">
	import { onMount } from "svelte";
	import { fetchNui } from "../utils/fetchNui";
	import { NUI_EVENTS } from "../constants/nuiEvents";
	import {
		DEFAULT_TIME,
		DEFAULT_DATE,
		TIMING,
		APP_INFO,
	} from "../constants";
	import { formatTime, formatDate } from "../utils/datetime";

	import type { AuthService } from "../services/authService.svelte";

	interface Props {
		authService: AuthService;
	}

	let { authService }: Props = $props();
	let info = $derived(APP_INFO[authService.jobType === "civilian" ? "leo" : authService.jobType] || APP_INFO.leo);

	let currentTime = $state(DEFAULT_TIME);
	let currentDate = $state(DEFAULT_DATE);

	/**
	 * Initializes the time update interval and cleans up on component destruction.
	 */
	onMount(() => {
		const timeInterval = setInterval(() => {
			const now = new Date();
			currentTime = formatTime(now);
			currentDate = formatDate(now);
		}, TIMING.timeUpdateInterval);

		return () => {
			clearInterval(timeInterval);
		};
	});
</script>

<div class="top-bar" role="region">
	<div class="terminal-context">
		{#if authService.isAuthorized}
			<span class="context-icon material-icons">shield</span>
			<div class="context-copy">
				<span class="context-department">{authService.playerInfo().department}</span>
				<span class="context-officer">{authService.playerInfo().rank} {authService.playerInfo().firstName} {authService.playerInfo().lastName}</span>
			</div>
		{:else}
			<span class="context-department">{info.title}</span>
		{/if}
	</div>
	<div class="utility-info">
		{#if authService.isAuthorized}
			<div class="utility-cell">
				<span class="utility-label">Callsign</span>
				<span class="utility-value accent">{authService.playerInfo().id || "Not set"}</span>
			</div>
			<div class="utility-separator"></div>
		{/if}
		<div class="utility-cell time-cell">
			<span class="utility-label">{currentDate}</span>
			<span class="utility-value">{currentTime}</span>
		</div>
	</div>
</div>

<style>
	.top-bar {
		background: #0c1117;
		min-height: 46px;
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 0 18px;
		color: var(--primary-text);
		font-size: 12px;
		font-weight: 500;
		border-bottom: 1px solid var(--border-primary);
		z-index: 10;
		position: relative;
		cursor: default;
	}

	:global([data-job-type="ems"]) .top-bar {
		background: rgba(18, 10, 10, 0.8);
		border-bottom-color: rgba(220, 50, 50, 0.12);
	}

	:global([data-job-type="doj"]) .top-bar {
		background: rgba(8, 12, 20, 0.8);
		border-bottom-color: rgba(180, 150, 60, 0.12);
	}

	.terminal-context,
	.utility-info {
		display: flex;
		align-items: center;
	}

	.context-icon {
		font-size: 18px;
		color: rgba(var(--accent-text-rgb), 0.72);
		margin-right: 8px;
	}

	.context-copy,
	.utility-cell {
		display: flex;
		flex-direction: column;
	}

	.context-department {
		color: rgba(255, 255, 255, 0.76);
		font-size: 10px;
		font-weight: 650;
		line-height: 1.2;
	}

	.context-officer,
	.utility-label {
		color: rgba(255, 255, 255, 0.32);
		font-size: 8px;
		line-height: 1.35;
		text-transform: uppercase;
		letter-spacing: 0.55px;
	}

	.utility-info { gap: 12px; }
	.utility-separator { width: 1px; height: 23px; background: rgba(255, 255, 255, 0.07); }
	.utility-value { color: rgba(255, 255, 255, 0.82); font-size: 10px; font-weight: 650; line-height: 1.25; }
	.utility-value.accent { color: rgba(var(--accent-text-rgb), 0.88); }
	.time-cell { text-align: right; }
	.time-cell .utility-label { text-transform: none; }

	@media (max-width: 1050px) {
		.context-officer { display: none; }
	}
</style>
