import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { computeCents, fmt, parseDecimal } from "@/lib/tip"

const PRESETS = [15, 18, 20, 25]

export default function App() {
  const [bill, setBill] = useState("")
  const [preset, setPreset] = useState<number | null>(18)
  const [custom, setCustom] = useState("")

  const billP = parseDecimal(bill)
  const customP = parseDecimal(custom, 100, "percent")
  const pctStr = preset !== null ? String(preset) : custom
  const ok = billP.value !== null && !billP.error && !customP.error && (preset !== null || customP.value !== null)
  const { tip, total } = ok ? computeCents(bill, pctStr) : { tip: 0, total: 0 }

  const reset = () => { setBill(""); setCustom(""); setPreset(18) }

  return (
    <main className="min-h-screen flex items-center justify-center p-4">
      <Card className="w-full max-w-[420px]">
        <CardHeader><CardTitle>Tip Calculator</CardTitle></CardHeader>
        <CardContent className="flex flex-col gap-5">
          <div className="flex flex-col gap-2">
            <Label htmlFor="bill">Bill</Label>
            <Input id="bill" type="text" inputMode="decimal" autoFocus placeholder="0.00" value={bill}
              onChange={(e) => setBill(e.target.value)} aria-invalid={!!billP.error}
              aria-describedby={billP.error ? "bill-hint" : undefined} />
            {billP.error && <p id="bill-hint" className="text-sm text-red-600">{billP.error}</p>}
          </div>
          <div className="flex flex-col gap-2">
            <span id="tip-label" className="text-sm font-medium leading-none">Tip</span>
            <div role="group" aria-labelledby="tip-label" className="grid grid-cols-4 gap-2">
              {PRESETS.map((p) => (
                <Button key={p} type="button" variant={preset === p ? "default" : "outline"} aria-pressed={preset === p}
                  onClick={() => { setPreset(p); setCustom("") }}>{p}%</Button>
              ))}
            </div>
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="custom">Custom %</Label>
            <Input id="custom" type="text" inputMode="decimal" placeholder="Other percent" value={custom}
              onChange={(e) => { setCustom(e.target.value); setPreset(null) }} aria-invalid={!!customP.error}
              aria-describedby={customP.error ? "custom-hint" : undefined} />
            {customP.error && <p id="custom-hint" className="text-sm text-red-600">{customP.error}</p>}
          </div>
          <div className="grid grid-cols-2 gap-4 border-t border-neutral-200 pt-5 dark:border-neutral-800" aria-live="polite">
            <div className="min-w-0"><div className="text-sm text-neutral-500">Tip</div><div data-testid="tip" className="break-all text-2xl sm:text-3xl font-semibold">{fmt(tip)}</div></div>
            <div className="min-w-0"><div className="text-sm text-neutral-500">Total</div><div data-testid="total" className="break-all text-2xl sm:text-3xl font-semibold">{fmt(total)}</div></div>
          </div>
          <Button type="button" variant="ghost" onClick={reset}>Reset</Button>
        </CardContent>
      </Card>
    </main>
  )
}
