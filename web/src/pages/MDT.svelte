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
    data-job-type={authService.jobType}
    data-department={departmentBrand.jobName}
    style={`--accent-rgb:${departmentBrand.accentRgb};--accent-text-rgb:${departmentBrand.accentTextRgb}`}
>
    <RadioPTT />
    <div class="mdt-window" aria-label="Mobile data terminal tablet">
        <span class="tablet-camera material-icons" aria-hidden="true">fiber_manual_record</span>
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
