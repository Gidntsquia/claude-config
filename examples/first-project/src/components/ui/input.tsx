import * as React from "react"
import { cn } from "@/lib/utils"
export function Input({ className, ...p }: React.ComponentProps<"input">) {
  return <input className={cn("h-10 w-full rounded-md border border-neutral-300 bg-transparent px-3 text-base outline-none focus-visible:ring-2 focus-visible:ring-blue-500 dark:border-neutral-700 aria-invalid:border-red-500 aria-invalid:ring-red-500", className)} {...p} />
}
