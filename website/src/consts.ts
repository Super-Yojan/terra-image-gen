export const SITE_TITLE = "Terra image";

/** Prefix an in-site path with the project Page base, `/terra-image-gen`. */
export const href = (path: string) =>
    `${import.meta.env.BASE_URL.replace(/\/$/, "")}${path === "/" ? "/" : path}`;

export interface NavPage {
    /** Route without the base, e.g. `/flash`. Full URLs link out. */
    path: string;
    label: string;
    blurb?: string;
}

export interface NavSection {
    title: string;
    path?: string;
    pages: NavPage[];
}

/** Every page, in reading order. The menu, the footer and the index use this list. */
export const menu: NavPage[] = [
    { path: "/flash", label: "Flash a card", blurb: "Raspberry Pi Imager on the Terra OS list: login, Wi-Fi and SSH set while it writes." },
    { path: "/build", label: "Build the image", blurb: "What is on the card, first boot, USB and hotspot links, and building it yourself." },
    { path: "/hardware-checklist", label: "Hardware checklist", blurb: "What still has to be checked on a real Pi 4 and Pi 5 with a Fusion HAT." },
];

export const sectionOf = (_path: string): NavSection | undefined => undefined;

export const isExternal = (path: string) => /^https?:/.test(path);

/** A nav path as a URL: external as is, in-site with the base and a trailing slash. */
export const link = (path: string) => {
    if (isExternal(path)) return path;
    if (path.startsWith("/#")) return `${href("/")}${path.slice(1)}`;
    return path === "/" ? href("/") : `${href(path)}/`;
};
