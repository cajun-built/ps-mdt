<script lang="ts">
    import {onMount} from "svelte";
    import {useNuiEvent} from "@/utils/useNuiEvent";
    import {setupDevelopmentMode} from "@/utils/developmentMode";
    import {createAuthService} from "../services/authService.svelte";
    import {createTabService} from "../services/tabService.svelte";
    import {settingsService} from "../services/settingsService.svelte";
    import {createInstanceStateService} from "../services/instanceStateService.svelte";
    import {NUI_EVENTS} from "@/constants/nuiEvents";
    import {fetchNui} from "@/utils/fetchNui";
    import {globalNotifications} from "../services/notificationService.svelte";
    import TopBar from "../components/TopBar.svelte";
    import NavigationPills from "../components/NavigationPills.svelte";
    import InstanceTabs from "../components/InstanceTabs.svelte";
    import ContentArea from "../components/ContentArea.svelte";
    import RadioPTT from "../components/RadioPTT.svelte";
    import {resolveDepartmentBrand} from "../utils/departmentBranding";
    import {
        DEFAULT_UI_ZOOM,
        getUiZoomLayout,
        normalizeUiZoom,
        readStoredUiZoom,
        UI_PREFERENCES_STORAGE_KEY,
        UI_ZOOM_EVENT,
    } from "../utils/uiZoom";
    import type {AuthUpdateData} from "@/interfaces/IUser";
    import {embedState} from "../stores/embedState.svelte";

    function closeEmbedded() {
        void fetchNui(NUI_EVENTS.NAVIGATION.CLOSE_UI);
    }

    const authService = createAuthService();
    const tabService = createTabService();
    const instanceStateService = createInstanceStateService(tabService);

    let departmentBrand = $derived(resolveDepartmentBrand(
        authService.playerData?.job?.name,
        authService.playerData?.job?.label,
        authService.jobType,
    ));
    let activeComponent = $derived(tabService.getActiveComponent());
    let uiZoom = $state(DEFAULT_UI_ZOOM);
    let uiZoomLayout = $derived(getUiZoomLayout(uiZoom));

    onMount(() => {
        uiZoom = readStoredUiZoom(localStorage.getItem(UI_PREFERENCES_STORAGE_KEY));

        const handleUiZoom = (event: Event) => {
            uiZoom = normalizeUiZoom((event as CustomEvent<number>).detail);
        };
        window.addEventListener(UI_ZOOM_EVENT, handleUiZoom);

        authService.checkAuth();
        settingsService.loadColorConfig();
        setupInstanceCoordination();
        loadMissedHearings();

        return () => window.removeEventListener(UI_ZOOM_EVENT, handleUiZoom);
    });

    // Global court reminder toast — shows on any tab, not just the calendar
    useNuiEvent<{ title?: string; scheduled_at?: string | number; location?: string }>(
        "courtReminder",
        (data) => {
            const raw = data?.scheduled_at;

            const num = Number(raw);

            const date = raw
                ? new Date(num < 1e12 ? num * 1000 : num)
                : null;

            const when =
                date && !isNaN(date.getTime())
                    ? ` (${date.toLocaleString("en-US", {
                        hour: "2-digit",
                        minute: "2-digit",
                    })})`
                    : "";

            const where = data?.location
                ? ` — ${data.location}`
                : "";

            globalNotifications.info(
                `Appointment: ${data?.title ?? "Hearing"}${when}${where}`
            );
        }
    );

    // On first MDT open, surface hearings whose reminder fired while offline
    async function loadMissedHearings(): Promise<void> {
        try {
            const missed = await fetchNui<Array<{ title: string; scheduled_at?: string }>>(
                NUI_EVENTS.COURT.GET_MISSED,
                {},
                [],
            );
            if (Array.isArray(missed) && missed.length > 0) {
                const titles = missed.slice(0, 3).map((m) => m.title).join(", ");
                const extra = missed.length > 3 ? ` +${missed.length - 3}` : "";
                globalNotifications.info(`Missed Appointment: ${titles}${extra}`);
            }
        } catch {
            /* ignore */
        }
    }

    function setupInstanceCoordination(): void {
        $effect(() => {
            const activeInstance = tabService.getActiveInstance();
            if (activeInstance) {
                instanceStateService.switchToInstance(
                    activeInstance.id,
                    activeInstance.currentTab,
                );
            }
        });
    }

    useNuiEvent<AuthUpdateData>(
        NUI_EVENTS.AUTH.UPDATE_AUTH,
        (data: AuthUpdateData) => {
            authService.updateAuthState(data);
        },
    );

    setupDevelopmentMode();

    if (typeof document !== 'undefined') {
        let lastFocusedInput: HTMLElement | null = null;
        let refocusPending = false;

        document.addEventListener('focusin', (e) => {
            const el = e.target as HTMLElement;
            if (el.tagName === 'INPUT' || el.tagName === 'SELECT' || el.tagName === 'TEXTAREA' || el.isContentEditable) {
                lastFocusedInput = el;
                refocusPending = false;
            }
        });

        document.addEventListener('focusout', (e) => {
            const fe = e as FocusEvent;
            const el = e.target as HTMLElement;
            // Skip SELECT elements - their dropdown interaction triggers focusout with null relatedTarget
            if (el.tagName === 'SELECT') return;
            if (fe.relatedTarget === null && lastFocusedInput === el && !refocusPending) {
                refocusPending = true;
                requestAnimationFrame(() => {
                    if (lastFocusedInput && (!document.activeElement || document.activeElement === document.body)) {
                        lastFocusedInput.focus();
                    }
                    refocusPending = false;
                });
            }
        });

    }
</script>

<main
    class="mdt-container"
    class:embedded={embedState.active}
    data-job-type={authService.jobType}
    data-department={departmentBrand.jobName}
    style={`--accent-rgb:${departmentBrand.accentRgb};--accent-text-rgb:${departmentBrand.accentTextRgb}`}
>
    <RadioPTT />
    <div class="mdt-window" aria-label="Mobile data terminal">
        {#if embedState.active}
            <header class="embedded-title">
                <span class="embedded-icon material-icons" aria-hidden="true">computer</span>
                <span class="embedded-name">MDT / CAD</span>
                <button class="embedded-control" title="Minimize to desktop" onclick={closeEmbedded}>
                    <span class="material-icons">remove</span>
                </button>
                <button class="embedded-control close" title="Close" onclick={closeEmbedded}>
                    <span class="material-icons">close</span>
                </button>
            </header>
        {:else}
            <span class="tablet-camera material-icons" aria-hidden="true">fiber_manual_record</span>
        {/if}
        <div
            class="mdt-interface"
            style={`zoom:${uiZoomLayout.zoom};width:${uiZoomLayout.width};height:${uiZoomLayout.height}`}
        >
            <div class="mdt-content">
                {#if !authService.isCivilian}
                    <div class="mdt-navigation">
                        {#if authService.isAuthorized}
                            <NavigationPills {tabService} jobType={authService.jobType} {authService} brand={departmentBrand}/>
                        {/if}
                    </div>
                {/if}
                <div class="mdt-main-content">
                    {#if activeComponent !== "dashboard"}
                        <TopBar {authService} />
                        {#if !authService.isCivilian}
                            <InstanceTabs {tabService}/>
                        {/if}
                    {/if}
                    <ContentArea
                            {authService}
                            {tabService}
                            {instanceStateService}
                    />
                </div>
            </div>
        </div>
    </div>
</main>

<style>
    .mdt-container {
        position: fixed;
        top: 0;
        left: 0;
        width: 100vw;
        height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 1000;
        padding: 4vh 5vw;
        background: transparent;
    }

    .mdt-window {
        width: 88vw;
        height: 84vh;
        padding: 13px;
        background: #030609;
        border-radius: 30px;
        overflow: visible;
        display: flex;
        flex-direction: column;
        box-shadow:
            0 34px 90px rgba(0, 0, 0, 0.72),
            0 0 0 1px rgba(255, 255, 255, 0.09),
            inset 0 0 0 1px rgba(255, 255, 255, 0.045);
        border: 1px solid rgba(0, 0, 0, 0.95);
        position: relative;
        opacity: 1;
    }

    .tablet-camera {
        position: absolute;
        top: 3px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 3;
        color: rgba(79, 98, 118, 0.75);
        font-size: 7px;
        line-height: 7px;
        text-shadow: 0 0 4px rgba(36, 132, 220, 0.35);
    }

    :global([data-job-type="ems"]) .mdt-window {
        border-color: rgba(220, 50, 50, 0.15);
        box-shadow: 0 20px 40px rgba(20, 8, 8, 0.4), 0 0 60px rgba(220, 50, 50, 0.04);
    }

    :global([data-job-type="doj"]) .mdt-window {
        border-color: rgba(180, 150, 60, 0.15);
        box-shadow: 0 20px 40px rgba(8, 12, 20, 0.4), 0 0 60px rgba(30, 58, 138, 0.04);
    }

    .mdt-interface {
        width: 100%;
        height: 100%;
        display: flex;
        flex-direction: column;
        overflow: hidden;
        border: 1px solid rgba(255, 255, 255, 0.075);
        border-radius: 18px;
        background: #0c1015;
        box-shadow: inset 0 0 24px rgba(0, 0, 0, 0.32);
    }

    .mdt-content {
        display: flex;
        height: 100%;
        min-height: 0;
    }

    .mdt-navigation {
        width: 184px;
        flex: 0 0 184px;
        background: #0a0e13;
        display: flex;
        border-right: 1px solid rgba(255, 255, 255, 0.07);
        min-height: 0;
    }

    .mdt-main-content {
        display: flex;
        flex-direction: column;
        flex: 1;
        min-width: 0;
        width: 100%;
        background: #0e1319;
    }

    /* Inside the LEO workstation: a maximized window above its 48px taskbar. */
    .mdt-container.embedded {
        height: calc(100vh - 48px);
        padding: 0;
    }

    .mdt-container.embedded .mdt-window {
        width: 100%;
        height: 100%;
        padding: 0;
        border: 0;
        border-radius: 0;
        box-shadow: none;
        background: #0a0e13;
    }

    .mdt-container.embedded .mdt-interface {
        /* Share the window with the title bar instead of taking its full height. */
        flex: 1;
        min-height: 0;
        height: auto !important;
        border: 0;
        border-radius: 0;
        box-shadow: none;
    }

    .embedded-title {
        height: 34px;
        flex: none;
        display: flex;
        align-items: center;
        gap: 8px;
        padding-left: 12px;
        background: #070a0e;
        border-bottom: 1px solid rgba(255, 255, 255, 0.07);
        color: rgba(255, 255, 255, 0.8);
        font-size: 12px;
        user-select: none;
    }

    .embedded-icon {
        font-size: 16px;
        color: rgb(var(--accent-rgb, 59 130 246));
    }

    .embedded-name {
        flex: 1;
    }

    .embedded-control {
        width: 46px;
        height: 100%;
        border: 0;
        background: transparent;
        color: rgba(255, 255, 255, 0.75);
        display: grid;
        place-items: center;
        cursor: default;
    }

    .embedded-control .material-icons {
        font-size: 16px;
    }

    .embedded-control:hover {
        background: rgba(255, 255, 255, 0.08);
    }

    .embedded-control.close:hover {
        background: #c42b1c;
        color: #fff;
    }

    @media (max-width: 1200px), (max-height: 720px) {
        .mdt-container { padding: 3vh 3vw; }
        .mdt-window {
            width: 92vw;
            height: 88vh;
            padding: 10px;
            border-radius: 24px;
        }
        .mdt-interface { border-radius: 15px; }
        .mdt-navigation {
            width: 168px;
            flex-basis: 168px;
        }
    }
</style>
