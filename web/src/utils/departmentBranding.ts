import type { JobType } from "../interfaces/IUser";

export interface DepartmentBrand {
	jobName: string;
	name: string;
	shortName: string;
	logo: string;
	accentRgb: string;
	accentTextRgb: string;
	icon: string;
}

const BUILT_IN: Record<string, Omit<DepartmentBrand, "jobName">> = {
	brpd: {
		name: "Baton Rouge Police Department",
		shortName: "BRPD",
		logo: "./images/departments/police.png",
		accentRgb: "30, 94, 170",
		accentTextRgb: "147, 197, 253",
		icon: "local_police",
	},
	ebrso: {
		name: "East Baton Rouge Sheriff's Office",
		shortName: "EBRSO",
		logo: "./images/departments/police.png",
		accentRgb: "158, 112, 32",
		accentTextRgb: "253, 211, 125",
		icon: "local_police",
	},
	lsp: {
		name: "Louisiana State Police",
		shortName: "LSP",
		logo: "./images/departments/police.png",
		accentRgb: "24, 90, 157",
		accentTextRgb: "144, 202, 249",
		icon: "local_police",
	},
	police: {
		name: "Los Santos Police Department",
		shortName: "LSPD",
		logo: "./images/departments/police.png",
		accentRgb: "47, 128, 237",
		accentTextRgb: "147, 197, 253",
		icon: "local_police",
	},
	lspd: {
		name: "Los Santos Police Department",
		shortName: "LSPD",
		logo: "./images/departments/lspd.png",
		accentRgb: "47, 128, 237",
		accentTextRgb: "147, 197, 253",
		icon: "local_police",
	},
	bcso: {
		name: "Blaine County Sheriff's Office",
		shortName: "BCSO",
		logo: "./images/departments/bcso.png",
		accentRgb: "202, 145, 48",
		accentTextRgb: "253, 211, 125",
		icon: "local_police",
	},
	sahp: {
		name: "San Andreas Highway Patrol",
		shortName: "SAHP",
		logo: "./images/departments/sahp.png",
		accentRgb: "33, 150, 243",
		accentTextRgb: "144, 202, 249",
		icon: "local_police",
	},
	ambulance: {
		name: "Emergency Medical Services",
		shortName: "EMS",
		logo: "./images/departments/ambulance.png",
		accentRgb: "220, 50, 50",
		accentTextRgb: "252, 165, 165",
		icon: "local_hospital",
	},
	doj: {
		name: "Department of Justice",
		shortName: "DOJ",
		logo: "./images/departments/doj.png",
		accentRgb: "180, 150, 60",
		accentTextRgb: "224, 202, 131",
		icon: "account_balance",
	},
};

const FALLBACKS: Record<Exclude<JobType, "civilian">, Omit<DepartmentBrand, "jobName">> = {
	leo: BUILT_IN.brpd,
	ems: BUILT_IN.ambulance,
	doj: BUILT_IN.doj,
};

function safeJobName(value: string | undefined): string {
	return String(value || "")
		.trim()
		.toLowerCase()
		.replace(/[^a-z0-9_-]/g, "");
}

export function resolveDepartmentBrand(
	jobName: string | undefined,
	jobLabel: string | undefined,
	jobType: JobType,
): DepartmentBrand {
	const key = safeJobName(jobName);
	const fallback = FALLBACKS[jobType === "civilian" ? "leo" : jobType] || BUILT_IN.police;
	const builtIn = BUILT_IN[key];
	const base = builtIn || fallback;

	return {
		...base,
		jobName: key || (jobType === "ems" ? "ambulance" : jobType === "doj" ? "doj" : "police"),
		name: builtIn?.name || jobLabel || base.name,
		shortName: builtIn?.shortName || (jobLabel ? jobLabel.replace(/[^A-Za-z]/g, "").slice(0, 5).toUpperCase() : base.shortName),
		logo: builtIn?.logo || `./images/departments/${key || "police"}.png`,
	};
}
