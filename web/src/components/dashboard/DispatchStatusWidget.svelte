<script lang="ts">
	/**
	 * Live dispatch breakdown: how many on-duty officers in this domain are
	 * currently in each status (Active / Busy / …). Self-contained — fetches and
	 * polls its own data so it can be dropped anywhere on the dashboard without
	 * touching the main dashboard payload.
	 */
	import { onMount, onDestroy } from "svelte";
	import { fetchNui } from "../../utils/fetchNui";
	import { isEnvBrowser } from "../../utils/misc";
	import { NUI_EVENTS } from "../../constants/nuiEvents";

	interface StatusCount {
		id: string;
		label: string;
		color: string;
		count: number;
	}
	interface Breakdown {
		total: number;
		statuses: StatusCount[];
	}

	let { detailed = false }: { detailed?: boolean } = $props();

	let breakdown = $state<Breakdown>({ total: 0, statuses: [] });
	let timer: ReturnType<typeof setInterval> | null = null;

	async function load() {
		try {
			const fallback = isEnvBrowser()
				? {
					total: 8,
					statuses: [
						{ id: "available", label: "Available", color: "#2ecc71", count: 4 },
						{ id: "assigned", label: "Assigned", color: "#3498db", count: 2 },
						{ id: "busy", label: "Busy", color: "#f39c12", count: 1 },
						{ id: "unavailable", label: "Unavailable", color: "#e74c3c", count: 1 },
					],
				}
				: { total: 0, statuses: [] };
			const res = await fetchNui<Breakdown>(
				NUI_EVENTS.MAP.GET_OFFICER_STATUS_BREAKDOWN,
				{},
				fallback,
			);
			if (res && Array.isArray(res.statuses)) breakdown = res;
		} catch {
			/* keep last good values on a transient failure */
		}
	}

	onMount(() => {
		load();
		timer = setInterval(load, 15000);
	});
	onDestroy(() => {
		if (timer) {
			clearInterval(timer);
			timer = null;
		}
	});
</script>

{#if breakdown.statuses.length > 0}
	<div class="dispatch-status" class:detailed aria-label="Officer status breakdown">
		{#each breakdown.statuses as s (s.id)}
			<div class="ds-chip" class:ds-muted={s.count === 0}>
				<span class="ds-dot" style="background:{s.color}"></span>
				<span class="ds-label">{s.label}</span>
				<span class="ds-count">{s.count}</span>
			</div>
		{/each}
	</div>
{:else if detailed}
	<div class="status-empty">No active unit status data</div>
{/if}

<style>
	.dispatch-status {
		display: flex;
		align-items: center;
		gap: 12px;
	}
	.dispatch-status.detailed {
		width: 100%;
		flex-direction: column;
		align-items: stretch;
		gap: 0;
	}
	.detailed .ds-chip {
		min-height: 34px;
		padding: 0 2px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.055);
	}
	.detailed .ds-chip:last-child { border-bottom: 0; }
	.detailed .ds-label {
		color: rgba(255, 255, 255, 0.65);
		font-size: 11px;
		font-weight: 520;
	}
	.detailed .ds-count {
		margin-left: auto;
		color: rgba(255, 255, 255, 0.88);
		font-size: 12px;
	}
	.ds-chip {
		display: flex;
		align-items: center;
		gap: 5px;
		font-size: 11px;
		color: rgba(255, 255, 255, 0.82);
	}
	.ds-chip.ds-muted {
		opacity: 0.4;
	}
	.ds-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		flex: 0 0 auto;
		box-shadow: 0 0 6px rgba(0, 0, 0, 0.4);
	}
	.ds-count {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	.ds-label {
		color: rgba(255, 255, 255, 0.55);
	}
	.status-empty {
		padding: 22px 4px;
		color: rgba(255, 255, 255, 0.28);
		font-size: 11px;
		text-align: center;
	}
</style>
