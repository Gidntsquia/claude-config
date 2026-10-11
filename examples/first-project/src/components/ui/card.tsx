import * as React from "react"
import { cn } from "@/lib/utils"
export function Card({ className, ...p }: React.ComponentProps<"div">) {
  return <div data-slot="card" className={cn("bg-white text-neutral-900 dark:bg-neutral-900 dark:text-neutral-50 flex flex-col gap-6 rounded-xl border border-neutral-200 dark:border-neutral-800 py-6 shadow-sm", className)} {...p} />
}
export function CardHeader({ className, ...p }: React.ComponentProps<"div">) { return <div className={cn("px-6", className)} {...p} /> }
export function CardTitle({ className, ...p }: React.ComponentProps<"h1">) { return <h1 className={cn("text-xl font-semibold leading-none", className)} {...p} /> }
export function CardContent({ className, ...p }: React.ComponentProps<"div">) { return <div className={cn("px-6", className)} {...p} /> }
