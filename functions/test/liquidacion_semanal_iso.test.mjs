import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  isoWeekBoundsRd,
  isoWeekFromRdDate,
  periodoIsoString,
} from "../lib/liquidacion_semanal.js";

describe("liquidacion_semanal ISO week", () => {
  it("periodoIsoString pads week", () => {
    assert.equal(periodoIsoString(2026, 3), "2026-W03");
    assert.equal(periodoIsoString(2026, 23), "2026-W23");
  });

  it("isoWeekFromRdDate for known Monday", () => {
    // 2026-06-09 is Tuesday in RD; ISO week should be W24 of 2026
    const w = isoWeekFromRdDate(2026, 5, 9);
    assert.equal(w.isoYear, 2026);
    assert.equal(w.isoWeek, 24);
  });

  it("isoWeekBoundsRd covers Mon-Sun RD civil", () => {
    const { inicio, fin } = isoWeekBoundsRd(2026, 24);
    assert.ok(inicio < fin);
    const spanMs = fin.getTime() - inicio.getTime();
    assert.ok(spanMs >= 6 * 86400000);
    assert.ok(spanMs < 8 * 86400000);
  });
});
