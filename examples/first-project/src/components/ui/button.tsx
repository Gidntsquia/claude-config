import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "@/lib/utils"
const buttonVariants = cva(
  "inline-flex items-center justify-center rounded-md text-sm font-medium h-10 px-4 cursor-pointer focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500",
  { variants: { variant: {
    default: "bg-neutral-900 text-white hover:bg-neutral-700 dark:bg-neutral-50 dark:text-neutral-900 dark:hover:bg-neutral-200",
    outline: "border border-neutral-300 bg-white hover:bg-neutral-100 dark:border-neutral-700 dark:bg-neutral-900 dark:hover:bg-neutral-800",
    ghost: "hover:bg-neutral-100 dark:hover:bg-neutral-800" } },
    defaultVariants: { variant: "default" } })
export function Button({ className, variant, ...p }: React.ComponentProps<"button"> & VariantProps<typeof buttonVariants>) {
  return <button className={cn(buttonVariants({ variant }), className)} {...p} />
}
