import * as React from "react"
import { cn } from "@/lib/utils"
export function Label({ className, ...p }: React.ComponentProps<"label">) {
  return <label className={cn("text-sm font-medium leading-none", className)} {...p} />
}
