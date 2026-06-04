// Committed headline file 3 of 8. Each file independently exercises the full Panda
// CSS surface — css(), cva(), styled(), and the stack/flex/grid patterns — against the
// generated ./styled-system types. Identical in structure to what pandagen.mjs emits.
//
// Eight files is past the 4-module saturation point (see README "Mechanism"): type-check
// these alone and the full ~489K-instantiation gap is already present — no generator
// needed. `npm run diag` shows tsc ≈ 166K vs tsgo ≈ 655K instantiations, 0 errors both.
import * as React from "react";
import { css, cva } from "styled-system/css";
import { styled } from "styled-system/jsx";
import { stack, flex, grid } from "styled-system/patterns";

const recipe3 = cva({
  base: { display: "flex", borderRadius: "md", px: "4", py: "2", fontWeight: "medium" },
  variants: {
    tone: { primary: { bg: "blue.500", color: "white" }, ghost: { bg: "transparent", color: "gray.700" } },
    size: { sm: { fontSize: "sm", px: "2" }, lg: { fontSize: "lg", px: "6" } },
  },
  defaultVariants: { tone: "primary", size: "sm" },
});
const Box3 = styled("div");

export function Panel3({ tone, size }: { tone?: "primary" | "ghost"; size?: "sm" | "lg" }) {
  const cls = css({
    display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "4",
    p: { base: "2", md: "4", lg: "6" }, color: { base: "gray.800", _dark: "gray.100" },
    bg: "white", borderWidth: "1px", borderColor: "gray.200",
    _hover: { bg: "gray.50", shadow: "md" }, _focusWithin: { outline: "2px solid", outlineColor: "blue.400" },
    transition: "all 0.2s", fontSize: { base: "sm", lg: "md" },
  });
  return (
    <Box3 className={cls} data-tone={tone}>
      <div className={stack({ gap: "2", direction: "column" })}>
        <span className={recipe3({ tone, size })}>label 3</span>
        <div className={flex({ align: "center", justify: "space-between", gap: "3" })}>
          <em className={css({ color: "red.500", fontSize: "xs" })}>x</em>
        </div>
        <ul className={grid({ columns: 2, gap: "2" })}><li>a</li><li>b</li></ul>
      </div>
    </Box3>
  );
}
