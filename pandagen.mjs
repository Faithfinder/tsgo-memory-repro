// Generates N Panda CSS component files into ./src. Each file uses css() / cva() /
// styled() and patterns (stack/flex/grid) against Panda's generated styled-system
// types. Panda's SystemStyleObject is a very large structural type; this is the
// construct that dominates the real app's `tsc --generateTrace` hot files.
//
// Zero proprietary code — only public packages (react, @pandacss/dev).
//
// Usage: node pandagen.mjs [fileCount]   (default 800; or set FILES env var)
import { mkdirSync, writeFileSync, rmSync, readdirSync } from "node:fs";

const M = Number(process.argv[2] ?? process.env.FILES ?? 800);
const SRC = new URL("./src/", import.meta.url);
mkdirSync(SRC, { recursive: true });
// Remove only previously-generated files (f*.tsx). The committed headline files
// (src/example*.tsx) are left untouched — they reproduce the full gap on their own.
for (const name of readdirSync(SRC)) {
  if (/^f\d+\.tsx$/.test(name)) rmSync(new URL(name, SRC));
}

const f = (i) => `
import * as React from "react";
import { css, cva } from "styled-system/css";
import { styled } from "styled-system/jsx";
import { stack, flex, grid } from "styled-system/patterns";

const recipe${i} = cva({
  base: { display: "flex", borderRadius: "md", px: "4", py: "2", fontWeight: "medium" },
  variants: {
    tone: { primary: { bg: "blue.500", color: "white" }, ghost: { bg: "transparent", color: "gray.700" } },
    size: { sm: { fontSize: "sm", px: "2" }, lg: { fontSize: "lg", px: "6" } },
  },
  defaultVariants: { tone: "primary", size: "sm" },
});
const Box${i} = styled("div");

export function Panel${i}({ tone, size }: { tone?: "primary" | "ghost"; size?: "sm" | "lg" }) {
  const cls = css({
    display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "4",
    p: { base: "2", md: "4", lg: "6" }, color: { base: "gray.800", _dark: "gray.100" },
    bg: "white", borderWidth: "1px", borderColor: "gray.200",
    _hover: { bg: "gray.50", shadow: "md" }, _focusWithin: { outline: "2px solid", outlineColor: "blue.400" },
    transition: "all 0.2s", fontSize: { base: "sm", lg: "md" },
  });
  return (
    <Box${i} className={cls} data-tone={tone}>
      <div className={stack({ gap: "2", direction: "column" })}>
        <span className={recipe${i}({ tone, size })}>label ${i}</span>
        <div className={flex({ align: "center", justify: "space-between", gap: "3" })}>
          <em className={css({ color: "red.500", fontSize: "xs" })}>x</em>
        </div>
        <ul className={grid({ columns: 2, gap: "2" })}><li>a</li><li>b</li></ul>
      </div>
    </Box${i}>
  );
}
`;

for (let i = 0; i < M; i++) writeFileSync(new URL(`f${i}.tsx`, SRC), f(i));
console.log(`generated ${M} files in ./src`);
