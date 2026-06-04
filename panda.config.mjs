import { defineConfig } from "@pandacss/dev";

export default defineConfig({
  jsxFramework: "react",
  preflight: true,
  include: ["./src/**/*.{js,jsx,ts,tsx}"],
  exclude: [],
  theme: { extend: {} },
  outdir: "styled-system",
});
