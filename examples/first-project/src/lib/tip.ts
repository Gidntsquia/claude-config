export type Parsed = { value: number | null; error: string | null }
/** Parse a decimal string. Empty -> null, no error. */
export function parseDecimal(s: string, max?: number, what = "amount"): Parsed {
  const t = s.trim()
  if (t === "") return { value: null, error: null }
  if (!/^-?\d*\.?\d+$|^-?\d+\.$/.test(t)) return { value: null, error: `Enter a positive ${what}` }
  const n = Number(t)
  if (n < 0) return { value: null, error: `Enter a positive ${what}` }
  if (max !== undefined && n > max) return { value: null, error: `Enter ${max} or less` }
  return { value: n, error: null }
}
/** Exact half-up computation in integer arithmetic. bill string -> cents. */
function toCentsScaled(s: string): bigint {
  // returns bill in units of 1/10^k scaled to a common 1e6 scale
  const [i, f = ""] = s.trim().replace(/^\./, "0.").split(".")
  return BigInt(i + (f + "000000").slice(0, 6)) // 1e-6 dollars (extra digits truncated)
}
export function computeCents(bill: string, pct: string): { tip: number; total: number } {
  // bill (1e-6 $) * pct (1e-6 %) -> 1e-12 * /100 ; tip in cents = x / 1e12 * 100 / 100 ... do in BigInt
  const b = toCentsScaled(bill), p = toCentsScaled(pct)
  const billCents = (b + 5000n) / 10000n // round bill to cents
  // tip cents = billCents * p / (100 * 1e6), half-up
  const den = 100_000_000n
  const tip = (billCents * p * 2n + den) / (den * 2n)
  return { tip: Number(tip), total: Number(billCents + tip) }
}
export function fmt(cents: number): string {
  return (cents / 100).toLocaleString("en-US", { style: "currency", currency: "USD" })
}
