<script lang="ts">
	import type { DepartmentBrand } from "../utils/departmentBranding";

	let { brand, size = 70 }: { brand: DepartmentBrand; size?: number } = $props();
	let failed = $state(false);

	$effect(() => {
		brand.logo;
		failed = false;
	});
</script>

<div class="department-logo" style:width="{size}px" style:height="{size}px" aria-label={brand.name}>
	{#if !failed}
		<img src={brand.logo} alt="{brand.name} crest" onerror={() => (failed = true)} />
	{:else}
		<span class="material-icons" aria-hidden="true">{brand.icon}</span>
	{/if}
</div>

<style>
	.department-logo {
		display: grid;
		place-items: center;
		flex: 0 0 auto;
	}

	img {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: contain;
	}

	.material-icons {
		font-size: 0.58em;
		color: rgba(var(--accent-text-rgb), 0.9);
		background: rgba(var(--accent-rgb), 0.12);
		border: 1px solid rgba(var(--accent-rgb), 0.25);
		border-radius: 50%;
		padding: 0.55em;
	}
</style>
