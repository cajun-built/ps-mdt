<script lang="ts">
	import { ALL_PERMISSION_KEYS } from "@/constants/management";

	let permissions = [...ALL_PERMISSION_KEYS];
</script>

<div class="permissions">
	{#each permissions as permission}
		<div class="permission">{permission}</div>
	{/each}
</div>
