<script lang="ts">
	import { useNuiEvent } from "../utils/useNuiEvent";
	import { fetchNui } from "../utils/fetchNui";
	import { debugLog } from "../utils/debug";
	import { mdtStore } from "../stores/mdtStore";
	import { setDateTimeConfig } from "../utils/datetime";
	import { NUI_EVENTS } from "../constants/nuiEvents";
	import { onMount, type Snippet } from "svelte";

	let { children }: { children: Snippet } = $props();
	const isDev = import.meta.env.DEV;
	let _visibility = $state(isDev ? true : false);

	let store = {
		set visibility(value: boolean) {
			_visibility = value;
		},
		get visibility() {
			return _visibility;
		},
	};

	onMount(() => {
		useNuiEvent<{ visible: boolean; debugMode?: boolean; dateTime?: { TimeFormat?: string; DateFormat?: string } }>(
			NUI_EVENTS.NAVIGATION.SET_VISIBLE,
			(data) => {
				if (data.debugMode !== undefined) {
					mdtStore.setDebugMode(data.debugMode);
				}
				if (data.dateTime) {
					setDateTimeConfig(data.dateTime);
				}

				debugLog("VisibilityProvider received setVisible:", data);
				store.visibility = data.visible;
				if (data.visible) {
					void fetchNui(NUI_EVENTS.NAVIGATION.FOCUS_UI);
				}
			},
		);

		const keyHandler = (e: KeyboardEvent) => {
			if (store.visibility && (e.key === "Escape" || e.code === "Escape" || e.keyCode === 27)) {
				e.preventDefault();
				e.stopPropagation();
				store.visibility = false;
				void fetchNui(NUI_EVENTS.NAVIGATION.CLOSE_UI);
			}
		};

		window.addEventListener("keydown", keyHandler, true);

		return () => window.removeEventListener("keydown", keyHandler, true);
	});
</script>

{#if _visibility}
	{@render children()}
{/if}
