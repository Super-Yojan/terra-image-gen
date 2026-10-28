import { defineCollection } from "astro:content";
import { glob } from "astro/loaders";
import { ROUTES, routeOf } from "./plugins/remark-terra.mjs";

// The guides live beside the image source in examples/terra, so they also read on GitHub.
const docs = defineCollection({
    loader: glob({
        base: "../examples/terra",
        pattern: Object.keys(ROUTES),
        generateId: ({ entry }) => routeOf(entry),
    }),
});

export const collections = { docs };
