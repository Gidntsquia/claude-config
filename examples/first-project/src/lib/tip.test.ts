import { test, expect } from "bun:test"
import { computeCents, fmt, parseDecimal } from "./tip"
test("examples", () => {
  expect(computeCents("50", "20")).toEqual({ tip: 1000, total: 6000 })
  expect(computeCents("23.45", "18")).toEqual({ tip: 422, total: 2767 })
  expect(fmt(computeCents("1234.56", "20").total)).toBe("$1,481.47")
  expect(computeCents("0.10", "5")).toEqual({ tip: 1, total: 11 }) // 0.5c half-up
})
test("parse", () => {
  expect(parseDecimal("").error).toBeNull()
  expect(parseDecimal("-5").error).not.toBeNull()
  expect(parseDecimal("abc").error).not.toBeNull()
  expect(parseDecimal("150", 100).error).not.toBeNull()
})
