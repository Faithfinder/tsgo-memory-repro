// Generates N self-contained TS source files into ./src. Each file mirrors the
// dominant pattern in a real large React app (and the hottest files in its tsc
// trace): a React Query data hook + mutation, a Zod v3 schema with z.infer, a
// props type derived from the schema, and a JSX component that consumes them.
//
// Zero proprietary code — only public packages (react, @tanstack/react-query, zod).
//
// Usage: node generate.mjs [fileCount]   (default 1500; or set FILES env var)
import { mkdirSync, writeFileSync, rmSync } from "node:fs";

const N = Number(process.argv[2] ?? process.env.FILES ?? 1500);
const SRC = new URL("./src/", import.meta.url);
rmSync(SRC, { recursive: true, force: true });
mkdirSync(SRC, { recursive: true });

const file = (i) => `
import * as React from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";

const Schema${i} = z.object({
  id: z.string(),
  name: z.string(),
  count: z.number().optional(),
  tags: z.array(z.string()),
  kind: z.enum(["a", "b", "c"]),
  nested: z.object({ x: z.number(), y: z.string(), z: z.array(z.number()) }),
}).extend({ extra: z.record(z.string(), z.unknown()).optional() });
type Model${i} = z.infer<typeof Schema${i}>;

async function fetch${i}(id: string): Promise<Model${i}> {
  const r = await fetch("/api/${i}/" + id);
  return Schema${i}.parse(await r.json());
}

export function use${i}(id: string) {
  return useQuery({ queryKey: ["m${i}", id], queryFn: async () => fetch${i}(id), enabled: !!id });
}

export function useUpdate${i}() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (m: Partial<Model${i}>) => m,
    onSuccess: async () => qc.invalidateQueries({ queryKey: ["m${i}"] }),
  });
}

interface Props${i} { id: string; onPick?: (m: Model${i}) => void; variant: "x" | "y" | "z"; }

export function Card${i}({ id, onPick, variant }: Props${i}) {
  const { data, isLoading } = use${i}(id);
  const update = useUpdate${i}();
  const [open, setOpen] = React.useState(false);
  const items = data?.tags ?? [];
  if (isLoading) return <div className="loading" data-variant={variant} />;
  return (
    <section className={"card card-" + variant} onClick={() => setOpen((o) => !o)}>
      <header><h3>{data?.name}</h3><span>{data?.count ?? 0}</span></header>
      <ul>
        {items.map((t, k) => (
          <li key={k} title={t} onMouseEnter={() => onPick?.(data!)}>{t}</li>
        ))}
      </ul>
      {open && (
        <footer>
          <button type="button" onClick={() => update.mutate({ id, name: "x" })}>save</button>
          {data?.nested.z.map((n, k) => <em key={k}>{n}</em>)}
        </footer>
      )}
    </section>
  );
}
`;

for (let i = 0; i < N; i++) writeFileSync(new URL(`f${i}.tsx`, SRC), file(i));
console.log(`generated ${N} files in ./src`);
