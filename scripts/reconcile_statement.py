#!/usr/bin/env python3
"""Reconcile IndusInd bank-statement XLSX exports against PaisaTrack SMS data.

Supports two SMS sources:
  1. Sanitized parser fixtures (test/fixtures/sms/<bank>/*.expected.json) —
     the committed subset; useful for parser-precision checks.
  2. A JSON export of parsed transactions from the app DB (future: the real
     T-034 device check) — pass --transactions <file> with a list of
     normalized records (amount, direction, ref_id, balance_after, ts).

Matching ladder (strongest first):
  1. Ref containment: fixture ref_id inside the statement Description
     (works for UPI RRNs and ACH ref strings).
  2. Amount + direction + balance-after == statement Balance.
  3. Amount + direction + same-day date.
  4. Amount + direction, only if the candidate is UNIQUE across the whole
     statement (reported as 'amount-unique', lower confidence).

Statement rows never leave this script; the report contains aggregate stats
plus per-case status. Do NOT commit statement files or reports containing
row-level data (BankStatement/ is gitignored).

Usage:
  python3 scripts/reconcile_statement.py \
      --statements 'BankStatement/*.xlsx*' \
      --fixtures test/fixtures/sms/indusind \
      --out BankStatement/reconciliation_report.md
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import re
from pathlib import Path

import openpyxl


def load_statement_rows(pattern: str) -> list[dict]:
    rows: list[dict] = []
    for path in sorted(glob.glob(pattern)):
        wb = openpyxl.load_workbook(path, read_only=True)
        ws = wb.active
        started = False
        for r in ws.iter_rows(values_only=True):
            if r and r[0] == "Sr.no":
                started = True
                continue
            if started and r and isinstance(r[0], (int, float)):
                rows.append(
                    {
                        "date": str(r[1])[:10],
                        "type": r[2],
                        "desc": r[3] or "",
                        "debit": float(r[4] or 0),
                        "credit": float(r[5] or 0),
                        "balance": float(r[6]) if r[6] not in (None, "") else None,
                    }
                )
    # Overlapping statement windows produce duplicate rows; dedupe exactly.
    seen: dict = {}
    for r in rows:
        key = (r["date"], r["desc"], r["debit"], r["credit"], r["balance"])
        seen.setdefault(key, r)
    return list(seen.values())


def load_fixture_records(fixture_dir: str) -> list[dict]:
    records = []
    for path in sorted(Path(fixture_dir).glob("*.expected.json")):
        data = json.loads(path.read_text())
        ok = data.get("expected", {}).get("ok")
        if ok:
            ok["case"] = path.name.replace(".expected.json", "")
            records.append(ok)
    return records


def stmt_amount(row: dict, direction: str) -> float:
    return row["debit"] if direction == "debit" else row["credit"]


def reconcile(stmt: list[dict], records: list[dict]) -> dict:
    used: set[int] = set()
    results = []
    for rec in records:
        amount = float(rec["amount"])
        direction = rec["direction"]
        ref = rec.get("ref_id") or ""
        ref_masked = bool(re.match(r"^X{2,}", ref))
        balance = rec.get("balance_after")
        ts_date = (
            dt.datetime.fromtimestamp(rec["ts"] / 1000).date().isoformat()
            if rec.get("ts")
            else None
        )
        hit, how = None, None
        if ref and not ref_masked:
            for i, row in enumerate(stmt):
                if i in used:
                    continue
                if ref in row["desc"]:
                    hit, how = i, "ref"
                    break
        if hit is None and balance is not None:
            for i, row in enumerate(stmt):
                if i in used:
                    continue
                if (
                    abs(stmt_amount(row, direction) - amount) < 0.01
                    and row["balance"] is not None
                    and abs(row["balance"] - balance) < 0.01
                ):
                    hit, how = i, "amount+balance"
                    break
        if hit is None and ts_date:
            for i, row in enumerate(stmt):
                if i in used:
                    continue
                if abs(stmt_amount(row, direction) - amount) < 0.01 and row["date"] == ts_date:
                    hit, how = i, "amount+date"
                    break
        if hit is None:
            candidates = [
                i
                for i, row in enumerate(stmt)
                if i not in used and abs(stmt_amount(row, direction) - amount) < 0.01
            ]
            if len(candidates) == 1:
                hit, how = candidates[0], "amount-unique"
            else:
                results.append(
                    {
                        "case": rec["case"],
                        "status": "no-candidates" if not candidates else "ambiguous",
                        "candidates": len(candidates),
                        "amount": amount,
                        "direction": direction,
                        "ref_masked": ref_masked,
                    }
                )
                continue
        used.add(hit)
        row = stmt[hit]
        results.append(
            {
                "case": rec["case"],
                "status": "matched",
                "method": how,
                "stmt_date": row["date"],
                "stmt_desc": row["desc"][:70],
                "amount": amount,
                "direction": direction,
            }
        )
    return {"results": results, "stmt_count": len(stmt)}


def write_report(out_path: str, recon: dict, records_count: int) -> None:
    results = recon["results"]
    matched = [r for r in results if r["status"] == "matched"]
    nocand = [r for r in results if r["status"] == "no-candidates"]
    ambig = [r for r in results if r["status"] == "ambiguous"]
    lines = [
        "# SMS ↔ Bank Statement Reconciliation",
        "",
        f"Generated {dt.date.today().isoformat()} by scripts/reconcile_statement.py.",
        "Contains row-level bank data — do not commit.",
        "",
        f"- Statement rows (deduped across files): {recon['stmt_count']}",
        f"- SMS records checked: {records_count}",
        f"- Matched: {len(matched)}"
        f" ({', '.join(sorted({m['method'] for m in matched}))})",
        f"- No statement candidates (likely other account / altered amount): {len(nocand)}",
        f"- Ambiguous (masked ref + no balance/date to pin): {len(ambig)}",
        "",
        "| Case | Status | Method/Candidates | Amount | Statement row |",
        "|---|---|---|---|---|",
    ]
    for r in results:
        if r["status"] == "matched":
            lines.append(
                f"| {r['case']} | matched | {r['method']} | {r['direction']} "
                f"{r['amount']:.2f} | {r['stmt_date']} {r['stmt_desc']} |"
            )
        else:
            lines.append(
                f"| {r['case']} | {r['status']} | {r['candidates']} candidates | "
                f"{r['direction']} {r['amount']:.2f} | — |"
            )
    Path(out_path).write_text("\n".join(lines) + "\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--statements", required=True, help="glob of statement .xlsx files")
    ap.add_argument("--fixtures", help="fixture dir (test/fixtures/sms/<bank>)")
    ap.add_argument("--transactions", help="JSON list of normalized records from app DB")
    ap.add_argument("--out", required=True, help="markdown report path (gitignored dir!)")
    args = ap.parse_args()

    stmt = load_statement_rows(args.statements)
    if args.transactions:
        records = json.loads(Path(args.transactions).read_text())
    elif args.fixtures:
        records = load_fixture_records(args.fixtures)
    else:
        raise SystemExit("Provide --fixtures or --transactions")

    recon = reconcile(stmt, records)
    write_report(args.out, recon, len(records))
    matched = sum(1 for r in recon["results"] if r["status"] == "matched")
    print(f"{matched}/{len(records)} SMS records matched to statement rows; report: {args.out}")


if __name__ == "__main__":
    main()
